#!/bin/bash

if [[ $# == 0 || $# > 3 ]]
then
    echo "Usage: bash upload_basespace_bcl2fastq.sh [bcl2fastq output path] [basespace-cli config]"
else
    # Parse command-line arguments
    bcl2fastq_path="$1"
    bs_config="$2"

    # If BaseSpace configuration file is not specified, use default
    if [[ $bs_config == "" ]]
    then
        bs_config="default"
    fi

    # Load and list modules
    module load basespace-cli/0.8.12.590
    module list

    cd $bcl2fastq_path/

    # Get array of FASTQ filenames
    filenames=(*/*.fastq.gz)
    # Remove Lane identifier from filenames
    prefixes=(${filenames[@]/_L00[1-8]_/_})
    # Remove Sample identifiers and everything to the right of them to obtain filename prefix
    prefixes=(${prefixes[@]/_S[1-9]*_R[12]_*/})

    # Create Projects for each project-specific folder
    for project_name in $(printf "%q\n" "${prefixes[@]%%/*}" | sort -u)
    do
        bs -c $bs_config create project "${project_name}_bcl2fastq"
    done

    # Iterate over unique prefixes, uploading each set of files to the corresponding Project
    for prefix in $(printf "%q\n" "${prefixes[@]}" | sort -u)
    do
        project_name="$(dirname $prefix)_bcl2fastq"
        sample_name="$(basename $prefix)"
        bs -c $bs_config upload sample -p "$project_name" -i "$sample_name" ${prefix}_*
    done
fi
