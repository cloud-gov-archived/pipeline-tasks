#!/bin/bash

# Creates a new issue based on a github-release Concourse resource. Optionally
# closes old issues created by this task.
#
# Note: It is possible this task could close unintended tasks. However, this should be highly unlikely
# as we use a label that starts with `dependency-` and only find issues created by cg-ci-bot. To 
# avoid issues, don't use a label that starts with `dependency-`.

if [[ -z "$DEPENDENCY_NAME" ]] || [[ -z "$GH_REPO" ]] || [[ -z "$GH_TOKEN" ]] || [[ -z "$PROJECT_NAME" ]] || [[ -z "$SQUAD_LABEL" ]]; then
  cat <<EOF

Missing required environment variable(s). Please be sure the following are set:

  CLOSE_OLD_ISSUES: Close old issues created by this task to prevent issue build up. Ex: true
  DEPENDENCY_NAME: The name of the dependency to alert on. Ex: wazuh-agent
  GH_REPO: The GitHub repo in which to open the issue. Ex: https://github.com/cloud-gov/wazuh-agent
  GH_TOKEN: The GitHub personal access token to use to manage issues in the GH_REPO. Ex: nicetrynotgoingtohappen
  PROJECT_NAME: The name of the project to add the issue to. Ex: cloud.gov team
  SQUAD_LABEL: The name of the squad, matching GitHub squad lables, responsible for this issue. Ex: squad-platform.

EOF
  exit 1
fi

author="cg-ci-bot"

release_version=$(cat github-release/version)
release_url=$(cat github-release/url)

title="$DEPENDENCY_NAME ${release_version} is available"
body="$DEPENDENCY_NAME ${release_version} is available: $release_url"
label="dependency-$DEPENDENCY_NAME" 

# create the dependency label if it doesn't exist
existing_label=$(gh label list --json name | jq -r '.[] | select(.name=="'"$label"'") | .name') 
if [[ -z "$existing_label" ]]; then
  gh label create $label
fi

# close old issues if true
if [[ "true" == "$CLOSE_OLD_ISSUES" ]]; then
  issue_numbers=$(gh issue list \
    -l "maintenance" \
    -l "$SQUAD_LABEL" \
    -l "$label" \
    -s "open" \
    -A "$author" \
    --json "number" | jq -r '.[].number')
  for issue_number in $issue_numbers; do
    gh issue close $issue_number -c "New version available: $release_version"
  done
fi

# create the new issue
gh issue create \
  -l "maintenance" \
  -l "$SQUAD_LABEL" \
  -l "$label" \
  -p "$PROJECT_NAME" \
  -t "$title" \
  -b "$body"

