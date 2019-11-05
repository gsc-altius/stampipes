#!/bin/bash

set -e

here=$(dirname "$0")
cd "$here"

STAMPIPES=$PWD/../../..
export STAMPIPES
nextflow run "$STAMPIPES/processes/bwa/aggregate/basic.nf" \
  -profile test,docker \
  "$@"

# Verify
source ../../test_helper.bash

#function cmp_picard() {
#  name=$(basename "$1")
#  expected=$(grep -v '^#' "expected/$name")
#  actual=$(grep -v '^#' "output/$name")
#
#  echo "Comparing $name..."
#  diff <(echo "$expected") <(echo "$actual")
#}
#
#function cmp_starch() {
#  name=$(basename "$1")
#  if ! which unstarch &>/dev/null ; then
#    echo "Cannot verify $name, unstarch is not available"
#    return 0
#  fi
#  echo "Comparing $name..."
#  cmp <(unstarch "expected/$name") <(unstarch "output/$name") \
#    || (echo "$name does not match" ; false)
#}
#
#function cmp_bam() {
#  name=$(basename "$1")
#  if ! which samtools &>/dev/null ; then
#    echo "Cannot verify $name, samtools is not available"
#    return 0
#  fi
#  echo "Comparing $name..."
#  cmp <(samtools view "expected/$name") <(samtools view "output/$name") \
#    || (echo "$name does not match" ; false)
#
#}
set +e
#cmp_picard "tagcounts.txt" || echo "tagcounts differ"
#cmp_picard "MarkDuplicates.picard" || echo "dups differ"
#cmp_picard "CollectInsertSizeMetrics.picard" || echo "insert differ"
#cmp_picard "r1.spot.out" || echo "spot differ"
#
#cmp_starch "density.starch" || echo "density differ"
#
#cmp_bam "filtered.bam" || echo "filtered differ"
#cmp_bam "marked.bam" || echo "marked differ"
#
#cmp_picard "hs_motifs_svmlight.cols.txt"
#cmp_picard "hs_motifs_svmlight.rows.txt"
#cmp_picard "hs_motifs_svmlight.txt"
#cmp_picard "prox_dist.info"
verify check_text tagcounts.txt
verify check_text MarkDuplicates.picard
verify check_text CollectInsertSizeMetrics.picard
verify check_text r1.spot.out

verify check_text hs_motifs_svmlight.cols.txt
verify check_text hs_motifs_svmlight.ros.txt
verify check_text hs_motifs_svmlight.txt
verify check_text prox_dist.info

verify check_bam filtered.bam
verify check_bam marked.bam

verify check_starch density.starch
verify check_starch normalized.density.starch
verify check_starch mm_density.starch
verify check_starch normalized.mm_density.starch
verify check_text preseq.txt

echo "Testing completed successfully"
