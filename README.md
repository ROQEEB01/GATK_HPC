# MPB_SNP_GATK

A [Nextflow](https://www.nextflow.io/) + [GATK](https://gatk.broadinstitute.org/) SNP and INDEL calling pipeline for **Mountain Pine Beetle** (*Dendroctonus ponderosae*) whole-genome resequencing data, designed to run on a SLURM-managed HPC cluster (e.g., the [Digital Research Alliance of Canada](https://alliancecan.ca/)).

---

## Table of Contents

- [Overview](#overview)
- [Pipeline Workflow](#pipeline-workflow)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Usage](#usage)
- [Output](#output)
- [Variant Filtering Criteria](#variant-filtering-criteria)
- [Notes](#notes)
- [References](#references)
- [License](#license)

---

## Overview

This pipeline takes read-group-tagged, coordinate-sorted BAM files and performs GATK best-practices variant calling:

1. **BAM quality control** — detect and quarantine corrupted BAMs
2. **Add read groups** — tag BAMs with sample metadata required by GATK
3. **Index reference genome** — SAMtools, BWA, and GATK dictionary indices
4. **Mark duplicates** — per sample using GATK `MarkDuplicates`
5. **Call variants (GVCF mode)** — per sample using GATK `HaplotypeCaller`
6. **Joint genotyping** — cohort-level calls via `GenomicsDBImport` + `GenotypeGVCFs`
7. **Variant filtration** — hard-filter SNPs and INDELs with recommended thresholds
8. **Export tables** — per-variant and per-genotype summary tables

---

## Pipeline Workflow

```
Raw BAM files
      │
      ▼
┌─────────────────────────────┐
│  move_bad_bam.sh            │  Quarantine corrupted BAMs
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  add_read_groups.sh         │  Add @RG tags (skip existing / bad BAMs)
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  main.nf — IndexReference   │  samtools faidx, bwa index, gatk dict
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  main.nf — IndexBam         │  samtools index (per sample)
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  main.nf — CallVariants     │  MarkDuplicates → HaplotypeCaller (GVCF)
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  main.nf — JointGenotyping  │  GenomicsDBImport → GenotypeGVCFs
│                             │  SelectVariants → VariantFiltration
│                             │  VariantsToTable
└────────────┬────────────────┘
             │
             ▼
      Filtered VCFs & Tables
```

---

## Prerequisites

### Software

| Tool | Version Tested | Purpose |
|------|---------------|---------|
| [Nextflow](https://www.nextflow.io/) | 24.04.4 | Workflow manager |
| [GATK](https://gatk.broadinstitute.org/) | 4.6.1.0 | Variant calling and filtration |
| [BWA](https://github.com/lh3/bwa) | 0.7.18 | Reference genome indexing |
| [SAMtools](http://www.htslib.org/) | 1.20 | BAM manipulation and indexing |
| [HTSlib](http://www.htslib.org/) | 1.19 | VCF/BCF compression and indexing |
| Java | 21.0.1 | Required by GATK and Nextflow |

> **HPC users (DRAC/Compute Canada):** All dependencies are available via `module load`. See the `module load` line in `run_nextflow.slm`.

### Data

- **Aligned BAM files** — one per sample, produced by [BWA-MEM](https://github.com/lh3/bwa) or equivalent. BAMs do **not** need to be pre-sorted; the pipeline handles indexing.
- **Reference genome** — FASTA file (e.g., `ref/MPB_reference.fna`)

---

## Repository Structure

```
MPB_SNP_GATK/
├── main.nf                  # Nextflow pipeline (DSL2)
├── nextflow.config          # SLURM executor config and resource settings
├── run_nextflow.slm         # SLURM submission script
├── add_read_groups.sh       # Add @RG tags; skips existing outputs and bad BAMs
├── move_bad_bam.sh          # Quarantine corrupted BAMs via samtools quickcheck
├── LICENSE
└── README.md
```

---

## Usage

### 1. Prepare Your Data Directory

```
data/
└── *.bam          # Raw aligned BAM files (one per sample)

ref/
└── MPB_reference.fna
```

### 2. Quarantine Bad BAMs *(optional but recommended)*

```bash
bash move_bad_bam.sh
```

Checks all BAMs in `data/` with `samtools quickcheck` and moves any corrupted files to `data/bad_bam/`.

### 3. Add Read Groups

GATK requires `@RG` headers in every BAM. Run this once before submitting the pipeline:

```bash
bash add_read_groups.sh
```

Outputs tagged BAMs to `data/read_group/`. Already-processed BAMs and bad BAMs are skipped automatically.

### 4. Configure Paths

Edit `nextflow.config` to set your scratch directory:

```groovy
params {
    work_dir = "/scratch/<your-username>/SNP_calling/work"
}
```

Edit `run_nextflow.slm` to set your SLURM account and email:

```bash
#SBATCH --account=<your-allocation>
#SBATCH --mail-user=<your-email>
```

### 5. Submit the Pipeline

```bash
sbatch run_nextflow.slm
```

The pipeline runs on all BAMs matching `data/read_group/*.bam` and writes results to `results/`.

To resume a failed run without recomputing completed steps:

```bash
nextflow run main.nf -resume --bams "data/read_group/*.bam" --ref "ref/MPB_reference.fna" --outdir "results"
```

---

## Output

All final files are written to the `results/` directory:

| File | Description |
|------|-------------|
| `analysis-ready-snps-filteredGT.vcf.gz` | Final filtered SNP calls |
| `analysis-ready-snps-filteredGT.vcf.gz.tbi` | Tabix index for SNP VCF |
| `analysis-ready-indels-filteredGT.vcf.gz` | Final filtered INDEL calls |
| `analysis-ready-indels-filteredGT.vcf.gz.tbi` | Tabix index for INDEL VCF |
| `output_snps.table` | Per-variant and per-genotype SNP summary table |
| `output_indels.table` | Per-variant and per-genotype INDEL summary table |

Nextflow also generates execution reports in the working directory:

| File | Description |
|------|-------------|
| `timeline.html` | Per-process execution timeline |
| `trace.txt` | Resource usage per task |
| `report.html` | Full pipeline execution report |

---

## Variant Filtering Criteria

### SNPs

| Filter | Expression |
|--------|-----------|
| `QD_filter` | QD < 2.0 |
| `FS_filter` | FS > 60.0 |
| `MQ_filter` | MQ < 40.0 |
| `SOR_filter` | SOR > 4.0 |
| `MQRankSum_filter` | MQRankSum < -12.5 |
| `ReadPosRankSum_filter` | ReadPosRankSum < -8.0 |
| `DP_filter` *(genotype)* | DP < 10 |
| `GQ_filter` *(genotype)* | GQ < 10 |

### INDELs

| Filter | Expression |
|--------|-----------|
| `QD_filter` | QD < 2.0 |
| `FS_filter` | FS > 200.0 |
| `SOR_filter` | SOR > 10.0 |
| `DP_filter` *(genotype)* | DP < 10 |
| `GQ_filter` *(genotype)* | GQ < 10 |

Thresholds follow [GATK hard-filtering recommendations](https://gatk.broadinstitute.org/hc/en-us/articles/360035531112).

---

## Notes

- **Resumable:** Nextflow caches completed tasks. Re-submitting with `-resume` skips any steps that finished successfully.
- **Scratch space:** Set `params.work_dir` in `nextflow.config` to a high-throughput scratch filesystem. Intermediate files can be large.
- **Single-sample testing:** To test on one sample before a full run, pass the specific BAM path directly: `--bams "data/read_group/sample01_rg.bam"`.
- **Genotype filtering:** Final genotype-level DP and GQ filtering is applied via `grep -vE` on the VCF before bgzip compression, as GATK `SelectVariants --exclude-filtered` operates on site-level filters only.

---

## References

- McKenna, A. et al. (2010). The Genome Analysis Toolkit. *Genome Research*, 20(9), 1297–1303. https://doi.org/10.1101/gr.107524.110
- Van der Auwera, G. A. & O'Connor, B. D. (2020). *Genomics in the Cloud*. O'Reilly Media.
- Li, H. & Durbin, R. (2009). Fast and accurate short read alignment with Burrows-Wheeler Aligner. *Bioinformatics*, 25(14), 1754–1760. https://doi.org/10.1093/bioinformatics/btp324

---

## License

This project is licensed under the BSD 3-Clause License. See [LICENSE](LICENSE) for details.
