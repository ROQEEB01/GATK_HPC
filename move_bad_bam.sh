#!/bin/bash
# Checks all BAM files in data/ using samtools quickcheck.
# Moves any corrupted or incomplete BAMs to data/bad_bam/ for review.

set -euo pipefail

cd data
mkdir -p bad_bam

for bam in *.bam; do
    if ! samtools quickcheck "$bam"; then
        echo "Moving BAD BAM: $bam -> bad_bam/"
        mv "$bam" bad_bam/
    fi
done

echo "Done. Suspected bad BAM files have been moved to bad_bam/."
