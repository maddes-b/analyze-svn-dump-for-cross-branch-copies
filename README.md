# Analyze SVN dump for Cross Branch Copies and Mergeinfo

`analyze-svn-dump-for-cross-branch-copies.sh [csvsep=";|," | details=<0/1>] [debug=<n>]`
* csvsep=";" (or ",") - export main information as CSV
* details=\<0/1> - see all copied pathes
* debug=\<n> - set debug verbosity level


A GNU awk script that analyzes a SVN dump file (created via `svnadmin dump`) for svn copies across branchs and mergeinfos, especially not from/to trunk, e.g. vendor branches and tags.
This may help when converting a repository, e.g. to git, as not all tools detect those correctly, but maybe the conversion can be stopped at those revisions, fixed and converted further.

Known tools to fail on cross-branch copies and cross-branch merges (as of 2020-01):
* git svn - https://git-scm.com/docs/git-svn
* SubGit - https://subgit.com/

Promising tools to check out:
* reposurgeon - https://gitlab.com/esr/reposurgeon
