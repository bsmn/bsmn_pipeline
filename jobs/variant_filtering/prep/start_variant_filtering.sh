#!/bin/bash
#$ -cwd
#$ -pe threaded 1

trap "exit 100" ERR

set -o pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename $0) <sample>"
    exit 100
fi

SM=$1

source $(pwd)/$SM/run_info

# Link alignment files to $SM/alignment
awk -v sm="$SM" -v OFS='\t' '$1 == sm {print $2, $3}' $SAMPLE_LIST |head -1 \
|while read BAM LOC; do
     if [[ ! -f "$SM/alignment/$BAM" ]]; then # alignment file doesn't exist.
         echo "INFO: Linking alignment files to the sample directory ..."
         mkdir -p $SM/alignment
         ln -sf $(readlink -f $LOC) $SM/alignment/$BAM
         if [[ $FILETYPE == "cram" ]]; then
             ls -lh $LOC.crai &> /dev/null \
                && ln -sf $(readlink -f $LOC.crai) $SM/alignment/$BAM.crai \
                || ln -sf $(readlink -f ${LOC/.cram/.crai}) $SM/alignment/${BAM/.cram/.crai}
         else
             ls -lh $LOC.bai &> /dev/null \
                && ln -sf $(readlink -f $LOC.bai) $SM/alignment/$BAM.bai \
                || ln -sf $(readlink -f ${LOC/.bam/.bai}) $SM/alignment/${BAM/.bam/.bai}
         fi
     fi
 done
IFS=' ' read -ra PL <<< "$PLOIDY"
for pl in "${PL[@]}"; do
    if [[ ! -f "$SM/gatk-hc/$SM.ploidy_$pl.vcf.gz" ]]; then
        echo "ERROR: VCF files for $SM with ploidy $pl are not ready?"
        echo "ERROR: You may need to use prep/VCF_files.link.sh"
        exit 100;
    fi
done

eval "$(conda shell.bash hook)"
conda activate --no-stack $CONDA_ENV

printf -- "[$(date)] Start submitting variant filtering jobs.\n---\n"

if [[ $RUN_FILTERS = "False" ]]; then
    echo "Skip this step. --run-filters option is not set."
else
    mkdir -p $SM/run_status
    if [[ $MULTI_ALIGNS = "False" ]]; then
        $PYTHON3 $PIPE_HOME/jobs/submit_filtering_jobs.py --queue $Q --ploidy $PLOIDY --sample-name $SM
        echo "---"
        echo "Submitted filtering jobs with single alignment."
    else
        $PYTHON3 $PIPE_HOME/jobs/submit_filtering_jobs.py --queue $Q --ploidy $PLOIDY --sample-name $SM --multiple-alignments
        echo "---"
        echo "Submitted filtering jobs with multiple alignments."
    fi
fi

conda deactivate

printf -- "---\n[$(date)] Finish submitting variant filtering jobs.\n"

