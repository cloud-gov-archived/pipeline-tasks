#!/bin/bash
# vim: set ft=sh

set -eux

if [ "$TERRAFORM_ACTION" != "plan" ] && \
    [ "$TERRAFORM_ACTION" != "apply" ] && \
    [ "$TERRAFORM_ACTION" != "0.12checklist" ]; then
  echo 'must set $TERRAFORM_ACTION to "plan" or "apply"' >&2
  exit 1
fi

TERRAFORM="${TERRAFORM_BIN:-terraform}"

DIR="terraform-templates"

set +x
# unset TF_VARs that are empty strings
for tfvar in "${!TF_VAR_@}"; do
	if [[ -z "${!tfvar}" ]]; then
		unset ${tfvar}
	fi
done
set -x

if [ -n "${TEMPLATE_SUBDIR:-}" ]; then
  DIR="${DIR}/${TEMPLATE_SUBDIR}"
fi

${TERRAFORM} get \
  -update \
  "${DIR}"

init_args=(
  "-backend=true"
  "-backend-config=encrypt=true"
  "-backend-config=bucket=${S3_TFSTATE_BUCKET}"
  "-backend-config=key=${STACK_NAME}/terraform.tfstate"
)
if [ -n "${TF_VAR_aws_region:-}" ]; then
  init_args+=("-backend-config=region=${TF_VAR_aws_region}")
fi
if [ -n "${TF_VAR_aws_access_key:-}" ]; then
  init_args+=("-backend-config=access_key=${TF_VAR_aws_access_key}")
fi
if [ -n "${TF_VAR_aws_secret_key:-}" ]; then
  init_args+=("-backend-config=secret_key=${TF_VAR_aws_secret_key}")
fi

${TERRAFORM} init \
  "${init_args[@]}" \
  "${DIR}"

if [ "${TERRAFORM_ACTION}" = "plan" ]; then
  ${TERRAFORM} "${TERRAFORM_ACTION}" \
    -refresh=true \
    -input=false \
    -out=./terraform-state/terraform.tfplan \
    "${DIR}"

  # Write a sentinel value; pipelines can alert to slack if set using `text_file`
  # Ensure that slack notification resource detects text file
  touch ./terraform-state/message.txt
  if ! ${TERRAFORM} show ./terraform-state/terraform.tfplan | grep 'This plan does nothing.' ; then
    echo "sentinel" > ./terraform-state/message.txt
  fi
else if [ "${TERRAFORM_ACTION}" = "0.12checklist" ]; then
  ${TERRAFORM} "${TERRAFORM_ACTION}" \
    "${DIR}"

  # Write a sentinel value; pipelines can alert to slack if set using `text_file`
  # Ensure that slack notification resource detects text file
  touch ./terraform-state/message.txt
  if ! ${TERRAFORM} show ./terraform-state/terraform.tfplan | grep 'This plan does nothing.' ; then
    echo "sentinel" > ./terraform-state/message.txt
  fi
else
  # run apply twice to work around bugs like this
  # https://github.com/hashicorp/terraform/issues/7235
  ${TERRAFORM} "${TERRAFORM_ACTION}" \
    -refresh=true \
    -input=false \
    -auto-approve \
    "${DIR}"
  ${TERRAFORM} "${TERRAFORM_ACTION}" \
    -refresh=true \
    -input=false \
    -auto-approve \
    "${DIR}"
  if [ -n "${TF_VAR_aws_region:-}" ]; then
    export AWS_DEFAULT_REGION="${TF_VAR_aws_region}"
  fi
  if [ -n "${TF_VAR_aws_access_key:-}" ]; then
    export AWS_ACCESS_KEY_ID="${TF_VAR_aws_access_key}"
  fi
  if [ -n "${TF_VAR_aws_secret_key:-}" ]; then
    export AWS_SECRET_ACCESS_KEY="${TF_VAR_aws_secret_key}"
  fi
  aws s3 cp "s3://${S3_TFSTATE_BUCKET}/${STACK_NAME}/terraform.tfstate" terraform-state
fi
