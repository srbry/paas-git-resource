#!/bin/sh

set -e

source $(dirname $0)/helpers.sh

it_can_get_from_url() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  get_uri $repo $dest | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref
}

it_can_get_from_url_at_ref() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit $repo)

  local dest=$TMPDIR/destination

  get_uri_at_ref $repo $ref1 $dest | jq -e "
    .version == {ref: $(echo $ref1 | jq -R .)}
  "

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref1

  rm -rf $dest

  get_uri_at_ref $repo $ref2 $dest | jq -e "
    .version == {ref: $(echo $ref2 | jq -R .)}
  "

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref2
}

it_can_get_from_url_at_branch() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_branch $repo branch-a)
  local ref2=$(make_commit_to_branch $repo branch-b)

  local dest=$TMPDIR/destination

  get_uri_at_branch $repo "branch-a" $dest | jq -e "
    .version == {ref: $(echo $ref1 | jq -R .)}
  "

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref1

  rm -rf $dest

  get_uri_at_branch $repo "branch-b" $dest | jq -e "
    .version == {ref: $(echo $ref2 | jq -R .)}
  "

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref2
}

it_can_get_from_url_only_single_branch() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  get_uri $repo $dest | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  ! git -C $dest rev-parse origin/bogus
}

it_honors_the_depth_flag() {
  local repo=$(init_repo)
  local firstCommitRef=$(make_commit $repo)

  make_commit $repo

  local lastCommitRef=$(make_commit $repo)

  local dest=$TMPDIR/destination

  get_uri_at_depth "file://"$repo 1 $dest |  jq -e "
    .version == {ref: $(echo $lastCommitRef | jq -R .)}
  "

  test "$(git -C $dest rev-parse HEAD)" = $lastCommitRef
  test "$(git -C $dest rev-list --all --count)" = 1
}

it_honors_the_depth_flag_for_submodules() {
  local repo_with_submodule_info=$(init_repo_with_submodule)
  local project_folder=$(echo $repo_with_submodule_info | cut -d "," -f1)
  local submodule_folder=$(echo $repo_with_submodule_info | cut -d "," -f2)
  local submodule_name=$(basename $submodule_folder)
  local project_last_commit_id=$(git -C $project_folder rev-parse HEAD)

  local dest_all=$TMPDIR/destination_all
  local dest_one=$TMPDIR/destination_one

  get_uri_with_submodules_all \
  "file://"$project_folder 1 $dest_all |  jq -e "
    .version == {ref: $(echo $project_last_commit_id | jq -R .)}
  "

  test "$(git -C $project_folder rev-parse HEAD)" = $project_last_commit_id
  test "$(git -C $dest_all/$submodule_name rev-list --all --count)" = 1

  get_uri_with_submodules_at_depth \
  "file://"$project_folder 1 $submodule_name $dest_one |  jq -e "
    .version == {ref: $(echo $project_last_commit_id | jq -R .)}
  "

  test "$(git -C $project_folder rev-parse HEAD)" = $project_last_commit_id
  test "$(git -C $dest_one/$submodule_name rev-list --all --count)" = 1
}

it_can_get_and_set_git_config() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  get_uri_with_config $repo $dest | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  test "$(git config --global core.pager)" == 'true'
  test "$(git config --global credential.helper)" == '!true long command with variables $@'
}

it_cant_get_commit_with_invalid_key() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  set +e
  output=$(get_uri_with_invalid_verification_key $repo $dest 2>&1)
  exit_code=$?
  set -e

  test "${exit_code}" == 2
  echo "${output}" | grep "Invalid GPG key in: abcd"
}

it_cant_get_commit_not_signed() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  set +e
  output=$(get_uri_with_verification_key $repo $dest 2>&1)
  exit_code=$?
  set -e

  test "${exit_code}" == 1
  echo "${output}" | grep "The commit ${ref} is not signed"
}

it_can_get_signed_commit() {
  local repo=$(init_repo)
  local ref=$(set -e ; make_signed_commit $repo)
  test "$ref" != ""
  local dest=$TMPDIR/destination

  get_uri_with_verification_key $repo $dest

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref
}

it_can_get_signed_commit_via_tag() {
  local repo=$(init_repo)
  local commit=$(set -e ; make_signed_commit $repo)
  local ref=$(make_annotated_tag $repo 'test-0.0.1' 'a message')
  local dest=$TMPDIR/destination

  get_uri_with_verification_key_and_tag_filter $repo $dest 'test-*' $ref

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $commit
}

it_cant_get_commit_signed_with_unknown_key() {
  local repo=$(init_repo)
  local ref=$(set -e ; make_signed_commit $repo)
  test "$ref" != ""
  local dest=$TMPDIR/destination

  set +e
  output=$(get_uri_with_unknown_verification_key $repo $dest 2>&1)
  exit_code=$?
  set -e

  test "${exit_code}" = 1
  echo "${output}" | grep "gpg: Can't check signature: No public key"  
}

it_cant_get_signed_commit_when_using_keyserver_and_bogus_key() {
  local repo=$(init_repo)
  local ref=$(set -e ; make_signed_commit $repo)
  test "$ref" != ""
  local dest=$TMPDIR/destination

  set +e
  output=$(get_uri_when_using_keyserver_and_bogus_key $repo $dest 2>&1)
  exit_code=$?
  set -e

  test "${exit_code}" = 123
  echo "${output}" | grep "gpg: \"abcd\" not a key ID: skipping"  
}

it_cant_get_signed_commit_when_using_keyserver_and_unknown_key_id() {
  local repo=$(init_repo)
  local ref=$(set -e ; make_signed_commit $repo)
  test "$ref" != ""
  local dest=$TMPDIR/destination

  set +e
  output=$(get_uri_when_using_keyserver_and_unknown_key $repo $dest 2>&1)
  exit_code=$?
  set -e

  echo $output
  test "${exit_code}" = 123
  echo "${output}" | grep "gpg: keyserver receive failed: No data"
}

it_can_get_signed_commit_when_using_keyserver() {
  local repo=$(init_repo)
  local ref=$(set -e ; make_signed_commit $repo)
  test "$ref" != ""
  local dest=$TMPDIR/destination

  get_uri_when_using_keyserver $repo $dest

  test -e $dest/some-file
  test "$(git -C $dest rev-parse HEAD)" = $ref
}

run it_can_get_from_url
run it_can_get_from_url_at_ref
run it_can_get_from_url_at_branch
run it_can_get_from_url_only_single_branch
run it_honors_the_depth_flag
run it_honors_the_depth_flag_for_submodules
run it_can_get_and_set_git_config
run it_cant_get_commit_with_invalid_key
run it_cant_get_commit_not_signed
run it_can_get_signed_commit
run it_cant_get_commit_signed_with_unknown_key
run it_cant_get_signed_commit_when_using_keyserver_and_bogus_key
run it_cant_get_signed_commit_when_using_keyserver_and_unknown_key_id
run it_can_get_signed_commit_when_using_keyserver
run it_can_get_signed_commit_via_tag
