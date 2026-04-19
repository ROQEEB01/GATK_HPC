#!/bin/bash
# Adds read group tags to all BAM files in data/.
# Skips BAMs that already have a corresponding *_rg.bam output file,
# and skips any BAM that fails samtools quickcheck.

set -euo pipefail

cd data
mkdir -p read_group

for bam in *.bam; do
    sample_name="${bam%%.bam}"
    output="read_group/${sample_name}_rg.bam"

    # Skip if output already exists
    if [[ -f "$output" ]]; then
        echo "Skipping $bam — output already exists."
        continue
    fi

    # Skip corrupted/incomplete BAMs
    if ! samtools quickcheck "$bam"; then
        echo "Skipping BAD BAM: $bam (failed quickcheck)"
        continue
    fi

    echo "Processing $bam -> $output"
    samtools addreplacerg \
        -r "ID:1" \
        -r "SM:${sample_name}" \
        -r "LB:lib1" \
        -r "PL:ILLUMINA" \
        -r "PU:unit1" \
        -o "$output" \
        "$bam"
done

echo "Done. All new/unprocessed BAM files have been handled."
