#!/bin/bash

set -eu

project="${1?}"
prefix="${2?}"

readarray -t csv

shopt -s extglob
csv=( "${csv[@]/#+([[:blank:]])/}" ) 
csv=( "${csv[@]/%+([[:blank:]])/}" ) 

echo "# Repo config line examples" > "{$project}.list"

for reporaw in "${csv[@]}"; do
	[[ "$reporaw" =~ ^#.* ]] && continue  # skip comments
	[[ "$reporaw" =~ ^[[:space:]]*$ ]] && continue  # skip empty lines

	distribution=$(echo "$reporaw" | xsv input -d \; | xsv select 1)
	component=$(echo "$reporaw" | xsv input -d \; | xsv select 2)
	archs=$(echo "$reporaw" | xsv input -d \; | xsv select 3 | tr -d \")
	debglob=$(echo "$reporaw" | xsv input -d \; | xsv select 4)
	slug="${project}-${distribution}-${component}"

	echo "deb [arch=${archs} signed-by=/etc/apt/trusted.gpg.d/${project}.gpg] https://repo.example.com ${distribution} ${component}" | tee -a "${project}.list"
	set -x
	aptly repo create \
		-distribution="$distribution" \
		-component="$component" \
		-architectures="$archs" \
		"$slug"
	aptly repo add "$slug" $debglob
	set +x
done

#TODO: All of this needs to detect data from the csv instead
set +x
for distribution in bookworm noble; do
	aptly publish repo \
		-component=, \
		-distribution="${distribution}" \
		${project}-${distribution}-{stable,nightly} \
		"${prefix}"
done
