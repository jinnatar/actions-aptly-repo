#!/bin/bash

set -eu

project="${1?}"
prefix="${2?}"

readarray -t csv

shopt -s extglob

## Canonicalize csv input
# Strip whitespace
csv=( "${csv[@]/#+([[:blank:]])/}" ) 
csv=( "${csv[@]/%+([[:blank:]])/}" ) 

# Drop unwanted lines
for i in "${!csv[@]}"; do
	if [[ "${csv[i]}" =~ ^#.* ]];then  # skip comments
		unset 'csv[i]'
		continue
	fi
	if [[ "${csv[i]}" =~ ^[[:space:]]*$ ]]; then # skip empty lines
		unset 'csv[i]'
		continue
	fi
done


>&2 echo "Canonicalized input;"
for repoline in "${csv[@]}"; do
	echo "repodef: ${repoline}"
done

## Create repos
>&2 echo "Creating repos:"
echo "# Repo config line examples" > "${project}.list"
for repoline in "${csv[@]}"; do
	distribution=$(echo "$repoline" | xsv input -d \; | xsv select 1)
	component=$(echo "$repoline" | xsv input -d \; | xsv select 2)
	archs=$(echo "$repoline" | xsv input -d \; | xsv select 3 | tr -d \")
	debglob=$(echo "$repoline" | xsv input -d \; | xsv select 4)
	slug="${project}-${distribution}-${component}"

	echo "deb [arch=${archs} signed-by=/etc/apt/trusted.gpg.d/${project}.gpg] https://repo.example.com/${prefix} ${distribution} ${component}" | tee -a "${project}.list"
	set -x
	aptly repo create \
		-distribution="$distribution" \
		-component="$component" \
		-architectures="$archs" \
		"$slug"
	aptly repo add "$slug" $debglob
	set +x
done

## Publish repos
distros=($(printf -- '%s\n' "${csv[@]}" | xsv input -d \; | xsv select 1 | sort -u | xargs))
>&2 echo "Publishing distros: ${distros[@]}"
for distribution in ${distros[@]}; do
	comps=($(printf -- '%s\n' "${csv[@]}" | xsv input -d \; | xsv search --select 1 "$distribution" | xsv select 2 | sort -u | xargs))
	>&2 echo "Publishing for $distribution the following components: ${comps[@]}"
	printf -v components '%s,' "${comps[@]}"
	repos=()
	for comp in "${comps[@]}"; do
		repos+=("${project}-${distribution}-${comp}")
	done

	set -x
	aptly publish repo \
		-component="${components::-1}" \
		-distribution="${distribution}" \
		"${repos[@]}" \
		"${prefix}"
	set +x
done
