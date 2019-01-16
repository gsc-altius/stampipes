#!/bin/bash

cd "$(dirname "$0")"

# Dependencies
source "$MODULELOAD"
module purge
module load jdk
module load nextflow
module load python/3.5.1

adapterfile="adapters.txt"

outdir="output"
workdir="work"

# Remove old stuff if necessary
if [[ -n "$REDO_ALIGNMENT" ]] ; then
  rm -rf "$outdir"
  rm -rf "$workdir"
  rm -rf "$adapterfile"
  python3 "$STAMPIPES/scripts/lims/upload_data.py" \
     --clear_align_stats \
     --alignment_id "$ALIGNMENT_ID"
fi

# Set up adapters
if [[ (-n "$ADAPTER_P7") && (-n "$ADAPTER_P5") ]]; then
  # Only update adapterfile if changed, to avoid needlessly recomputing work
  tmpfile=$(mktemp)
  echo -e "P7\t$ADAPTER_P7\nP5\t$ADAPTER_P5" > "$tmpfile"
  rsync --checksum "$tmpfile" "$adapterfile"
  rm "$tmpfile"
fi

# Tell LIMS we're starting alignment
echo \
python3 "$STAMPIPES/scripts/lims/upload_data.py" \
  -a "$LIMS_API_URL" \
  -t "$LIMS_API_TOKEN" \
  --alignment_id "$ALIGNMENT_ID" \
  --start_alignment_progress \
  --adapter_file "$ADAPTER_FILE" \
  --version_file "$VERSION_FILE"

# Run the whole process
nextflow run \
  "$STAMPIPES/processes/chip_seq_cut_and_run/alignment/process_bwa_paired_trimmed.nf" \
  -c "$STAMPIPES/nextflow.config" \
  -w "$workdir" \
  --r1 "$R1_FASTQ" \
  --r2 "$R2_FASTQ" \
  --adapter_file "$adapterfile"  \
  --genome "$BWAINDEX" \
  --outdir "$outdir" \
  --threads 3 \
  --readlength "$READLENGTH" \
  -profile cluster,modules \
  -resume

# Upload results
echo \
python3 "$STAMPIPES/scripts/lims/upload_data.py" \
  -a "$LIMS_API_URL" \
  -t "$LIMS_API_TOKEN" \
  -f "$FLOWCELL" \
  --alignment_id "$ALIGNMENT_ID" \
  --flowcell_lane_id "$FLOWCELL_LANE_ID" \
  --spotfile "$outdir/subsample.spot.out" \
  --countsfile "$outdir/tagcounts.txt" \
  --insertsfile "$outdir/CollectInsertSizeMetrics.picard" \
  --dupsfile "$outdir/MarkDuplicates.picard" \
  --finish_alignment
  #--spotdupfile ${SAMPLE_NAME}.rand.uniques.sorted.spotdups.txt \

