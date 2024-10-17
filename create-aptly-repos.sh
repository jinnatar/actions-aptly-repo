#!/bin/bash

set -eu

project="${1?}"
prefix="${2?}"
prefix_print="$prefix"
list_file_target="${project}.list"

# Data we expect from GHA env but give defaults for here that disable the feature to ease development.
# (GHA sets them to an empty value if not given instead of not setting them)
REPO_URL="${REPO_URL:-}"
GENERATE_REPO_LIST="${GENERATE_REPO_LIST:-"true"}"
GPG_KEY_ID="${GPG_KEY_ID:-}"
GPG_EXPORT_NAME="${GPG_EXPORT_NAME:-}"

# Contract a no-prefix prefix for printing purposes
if [[ "$(basename $prefix)" == "." ]]; then
	prefix_print=""
else
	# Only add the URL to prefix divider slash if we have a prefix
	prefix_print="/${prefix}"
fi

function repo_list_line(){
	local distribution="${1?}"
	local component="${2?}"
	local archs="${3?}"
	local signed_by=""

	if [[ "$GPG_EXPORT_NAME" != "" ]]; then
		signed_by="signed-by=/etc/apt/trusted.gpg.d/${GPG_EXPORT_NAME}"
	fi

	echo "# Example for enabling only the ${component} component on ${distribution}: " >> "$list_file_target"
	echo "deb [arch=${archs} ${signed_by}] ${REPO_URL}${prefix_print} ${distribution} ${component}" >> "$list_file_target"
}

## Read the repodef csv from stdin
readarray -t csv

## Canonicalize csv input
shopt -s extglob
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

# Check column count
columncount="$(printf -- '%s\n' "${csv[@]}" | xsv slice --no-headers -i 0 | xsv flatten --no-headers | wc -l)"

if [[ "$columncount" != 5 ]]; then
	>&2 echo "Wrong number of columns in repo definitions, forgot to escape arch list quoting?"
	exit 1
fi

## Create repos
>&2 echo "Creating repos:"
if [[ "$REPO_URL" != "" && "$GENERATE_REPO_LIST" == "true" ]]; then
	echo "# You probably want to use only one of the examples below!" > "$list_file_target"
fi
for repoline in "${csv[@]}"; do
	distribution=$(echo "$repoline" | xsv select 1)
	component=$(echo "$repoline" | xsv select 2)
	archs=$(echo "$repoline" | xsv select 3 | tr -d \")
	import=$(echo "$repoline" | xsv select 4)
	debglob=$(echo "$repoline" | xsv select 5)
	slug="${project}-${distribution}-${component}"

	set -x
	aptly repo create \
		-distribution="$distribution" \
		-component="$component" \
		-architectures="$archs" \
		"$slug"

	# Check if component is one to extend before we add new debs
	if [[ "$REPO_URL" != "" && "$import" == "true" ]]; then
		aptly mirror create \
			-keyring=~/.gnupg/pubring.kbx \
			"mirror-${slug}" \
			"$REPO_URL" \
			"$distribution" "$component"
		aptly mirror update \
			-keyring=~/.gnupg/pubring.kbx \
			"mirror-${slug}"
		aptly repo import \
			"mirror-${slug}" \
			"$slug" \
			Name  # Wildcard to accept any package
	fi

	# Add new debs
	aptly repo add "$slug" $debglob
	set +x
	if [[ "$REPO_URL" != "" && "$GENERATE_REPO_LIST" == "true" ]]; then
		repo_list_line "$distribution" "$component" "$archs"
	fi
done

## Publish repos per distribution
distros=($(printf -- '%s\n' "${csv[@]}" | xsv select 1 | sort -u | xargs))
>&2 echo "Publishing distros: ${distros[@]}"
publish_options=(-multi-dist)

if [[ "$GPG_KEY_ID" == "" ]]; then
	echo "::warning title=The input gpg_private_key has not been defined or is empty.::\
		Omitting gpg_private_key means the repo will NOT be signed and is not useful outside of local testing."
	publish_options+=(-skip-signing)
fi

for distribution in ${distros[@]}; do
	comps=($(printf -- '%s\n' "${csv[@]}" | xsv search --select 1 "$distribution" | xsv select 2 | sort -u | xargs))
	>&2 echo "Publishing for $distribution the following components: ${comps[@]}"
	printf -v components '%s,' "${comps[@]}"
	repos=()
	for comp in "${comps[@]}"; do
		repos+=("${project}-${distribution}-${comp}")
	done

	set -x
	aptly publish repo \
		${publish_options[@]} \
		-component="${components::-1}" \
		-distribution="${distribution}" \
		"${repos[@]}" \
		"${prefix}"
	set +x
done
