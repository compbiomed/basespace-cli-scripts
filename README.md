# Bash wrapper scripts for working with the BaseSpace command-line interface (CLI)

These scripts are written to be used with version 0.9 or greater of the BaseSpace [command-line interface (CLI)](https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview).

### `download_basespace_project.sh`
Usage:
`bash download_basespace_project.sh [options] -i|--id [Project ID]`
Options:
```
  -i, --id             BaseSpace Project ID (integer)
  -o, --output-path    Path where the FASTQ files will be written
                       (Default: current working directory)
  -c, --config         BaseSpace CLI configuration
                       (Default: 'default')
```
The Project files are retrieved from BaseSpace and placed in the specified output path.

The output path and all of its contents are then set to read-only permissions to prevent accidental deletion.

### `download_basespace_run.sh`
Usage:
  `bash download_basespace_run.sh [options] -i|--id [Run ID]`
Options:
```
  -i, --id             BaseSpace Run ID (integer)
  -o, --output-path    Path where the Run files will be written
                       (Default: current working directory)
  -c, --config         BaseSpace CLI configuration
                       (Default: 'default')
  -e, --exclude        Comma-separated list of extensions to exclude
                       (Default: 'jpg')
```
The Run files (except for any matching the specified set of extensions to exclude) retrieved from BaseSpace and placed in the specified output path.

The output path and all of its contents are then set to read-only permissions to prevent accidental deletion.

### `download_basespace_run_metadata.sh`
Usage:
  `bash download_basespace_run_metadata.sh [options] -i|--id [Run ID]`
Options:
```
  -i, --id             BaseSpace Run ID (integer)
  -o, --output-path    Path where a tar file will be written
                       (Default: current working directory)
  -c, --config         BaseSpace CLI configuration
                       (Default: 'default')
```
This script produces the tarball:
`[tarfile path]/[run name].tar.gz`
where `run name` is of the form:
`[yymmdd]_[instrument ID]_[run index]_[A or B][flowcell ID]`

This tarball contains all Run files *except for* those with the extensions:
`bci bgzf filter jpg locs`

The tarball is set to read-only permissions to prevent accidental deletion.

Note: this script assumes that it is in the same path as `download_basespace_run.sh`.

### `download_from_basespace.sh`
Usage:
  `bash download_from_basespace.sh [options] -r|--run-ids [RunID1,RunID2,...] -p|--project-ids [ProjectID1,ProjectID2,...]`
Options:
```
  -r, --run-ids        Comma-separated list of BaseSpace Run IDs (integers)
  -p, --project-ids    Comma-separated list of BaseSpace Project IDs (integers)
  -t, --tarfile-path   Path where a tarball of Run files will be written
                       (Default: current working directory)
  -f, --fastq-path     Path where directories of FASTQ files will be written
                       (Default: current working directory)
  -c, --config         BaseSpace CLI configuration
                       (Default: 'default')
```
This script performs the following tasks:
1. The script `download_basespace_run_metadata.sh` is used to retrieve the metadata for each Run, producing the tarballs:
   `[tarfile path]/[run name].tar.gz`
   where `run name` is of the form:
   `[yymmdd]_[instrument ID]_[run index]_[A or B][flowcell ID]`

2. The following directory is created for each Run:
   `[FASTQ path]/[run name]/`

3. The script `download_basespace_project.sh` is used to retrieve the `.fastq.gz` files for each Project.

4. The integrity of each `.fastq.gz` file is tested using `gzip -t` to ensure that it was correctly downloaded.

5. For each Run, the `.fastq.gz` files for each sample are concatenated across all lanes, e.g., the files:
   `SampleX_S1_L00*_R1_001.fastq.gz`
   are concatentated (in order, by lane) into:
   `[FASTQ path]/[run name]/SampleX_S1_R1_001.fastq.gz`

6. The tarball, each run-specific directory, and all of the FASTQ files contained in each of them are all set to read-only permissions to prevent accidental deletion.

Note: this script assumes that it is in the same path as `download_basespace_run_metadata.sh` and `download_basespace_project.sh`.

### `upload_basespace_bcl2fastq.sh`
Usage:
  `bash upload_basespace_bcl2fastq.sh [options]`
Options:
```
  -b, --bcl2fastq-path     Path containing bcl2fastq output
                           (Default: current working directory)
  -c, --config             BaseSpace CLI configuration
                           (Default: 'default')
```
A BaseSpace Project is created for each project-specific directory in the `bcl2fastq` output, and all of the FASTQ files in those directories are uploaded to the corresponding Projects.
