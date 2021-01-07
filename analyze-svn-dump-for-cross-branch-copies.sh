#!/bin/gawk -f

###
### analyze-svn-dump-for-cross-branch-copies.sh
###
### Parameters:
### * csvsep=";" (or ",") - export main information as CSV
### * details=1 - see all copied pathes
### * debug=<n> - set debug verbosity level
###
### Known issues:
### * If content of a property value contains svnadmin-dump-like property data, then the result is undefined.
###   /^PROPS-END$/, /^K [[:digit:]]+$/, /^D [[:digit:]]+$/
### * If content of a node contains svnadmin-dump-like record data, then the result is undefined.
###   /^Revision-number: [[:digit:]]+$/, /^Node-path: /
###
### Testing:
### analyze-svn-dump-for-cross-branch-copies.sh debug=1 <dumpfile> 2>&1 | less
###

###
### Copyright (C) 2021  Matthias Bücher, Germany <maddes@maddes.net>
###
### This program is free software: you can redistribute it and/or modify
### it under the terms of the GNU General Public License as published by
### the Free Software Foundation, either version 3 of the License, or
### (at your option) any later version.
###
### This program is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU General Public License for more details.
###
### You should have received a copy of the GNU General Public License
### along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

### Subversion dump format: https://svn.apache.org/repos/asf/subversion/trunk/notes/dump-load-format.txt
### GNU awk: https://www.gnu.org/software/gawk/manual/
### GNU awk and binary data: http://web.archive.org/web/20180501232815/http://www.awk-scripting.de:80/cgi-bin/wiki.cgi/scripting/BinaryData


###
### Function to Determine Branch from A Node Path
###
### ATTENTION! function code has to be adapted to the structure of the repository and its historical changes
function getBranchOfNodePath(nodepath,    branch, matches) {
  branch = ""
  ### --- A) Extended standard layout: /vendor/*, /tags/vendor/*
  if (match(nodepath, /^\/?(vendor\/[^/]*)/, matches)) {
    branch = "/" matches[1]
  } else
  if (match(nodepath, /^\/?(tags\/vendor\/[^/]*)/, matches)) {
    branch = "/" matches[1]
  } else
  ### --- B) standard layout: /branches/*, /tags/*, /trunk
  if (match(nodepath, /^\/?(branches\/[^/]*)/, matches)) {
    branch = "/" matches[1]
  } else
  if (match(nodepath, /^\/?(tags\/[^/]*)/, matches)) {
    branch = "/" matches[1]
  } else
  if (match(nodepath, /^\/?(trunk)(\/|$)/, matches)) {
    branch = "/" matches[1]
  } else
  ### --- C) error
  {
    printf("[ERROR] %09d: Cannot determine branch from %s. Please maintain function getBranchOfNodePath().\n", NR, nodepath) > "/dev/stderr"
    exit(1)
  }
  #
  return branch
}


###
### Functions for Initialization
###
function clearFileVars() {
  ## initialize file variables
  revision = ""
  ## initialize file arrays
  delete cross_branch_copies
  delete cross_branch_copies_first
  delete cross_branch_mergeinfos
}

function clearRevisionVars() {
  ## initialize revision variables
}

function clearNodePathVars() {
  ## initialize nodepath variables
  nodepath = ""
  nodecopyrev = ""
  nodecopypath = ""
}

function clearPropertyVars() {
  ## initialize property variables
  property_stage = 0
  property_key_action = ""
  property_key_length = 0
  property_key = ""
  property_key_relevant = 0
  property_value_length = 0
  property_value = ""
}

function clearProcessFlags() {
  ## initialize process variables
  process_revision = 0
  process_nodepath = 0
  process_properties = ""
}


###
### Function for Initialization
###
function processBranches(mergetype,    branchfrom, branchto) {
  branchfrom = getBranchOfNodePath(nodecopypath)
  branchto = getBranchOfNodePath(nodepath)
  #
  if (branchfrom != branchto) {
    if (debug >= 1) {
      printf("[debug] %09d: PROCESSING cross-branch %s %s (rev %s) to %s\n", NR, mergetype, branchfrom, nodecopyrev, branchto) > "/dev/stderr"
    }
    #
    cross_branch_copies[revision][branchfrom][branchto][nodepath]["nodecopypath"] = nodecopypath
    cross_branch_copies[revision][branchfrom][branchto][nodepath]["nodecopyrev"] = nodecopyrev
    if (!((branchfrom, branchto) in cross_branch_copies_first)) {
      cross_branch_copies_first[branchfrom, branchto] = revision
    }
  }
}


###
### Begin of awk Program
###
BEGIN {
  FS = "\n"
}


###
### Begin of File
###
BEGINFILE {
  if (debug >= 1) {
    printf("[debug] === debug level: %d, file: %s\n", debug, FILENAME) > "/dev/stderr"
  }
  ## initialize flags and variables
  clearFileVars()
  clearRevisionVars()
  clearNodePathVars()
  clearPropertyVars()
  clearProcessFlags()
}


###
### Revision Record
###
!(process_revision || process_nodepath || process_properties) && /^Revision-number: [[:digit:]]+$/ {
  if (debug >= 1) {
    printf("[debug] %09d: found %s\n", NR, $0) > "/dev/stderr"
  }
  #
  clearRevisionVars()
  clearNodePathVars()
  clearPropertyVars()
  clearProcessFlags()
  #
  process_revision = 1
  revision = gensub(/^Revision-number: /, "", 1, $0) + 0  ## addition forces number
  next
}

(process_revision) {
  if (/^$/) {  ## end of revision record
    process_revision = 0
    next
  }
  #
  if (/^Prop-content-length: [[:digit:]]+$/) {
    if (debug >= 3) {
      printf("[debug] %09d: found revision %s\n", NR, $0) > "/dev/stderr"
    }
    #
    process_properties = "revision"
    next
  }
  #
  next ## skip all other information
}


###
### Node Record
###
!(process_revision || process_nodepath || process_properties) && /^Node-path: / {
  if (debug >= 1) {
    printf("[debug] %09d: found %s\n", NR, $0) > "/dev/stderr"
  }
  #
  clearNodePathVars()
  clearPropertyVars()
  clearProcessFlags()
  #
  process_nodepath = 1
  nodepath = gensub(/^Node-path: /, "", 1, $0)
  next
}

(process_nodepath) {
  if (/^$/) {  ## end of node record
    if (nodecopypath) {
      processBranches("copy")
    }
    #
    process_nodepath = 0
    next
  }
  #
  if (/^Prop-content-length: [[:digit:]]+$/) {
    if (debug >= 3) {
      printf("[debug] %09d: found nodepath %s\n", NR, $0) > "/dev/stderr"
    }
    #
    process_properties = "nodepath"
    next
  }
  #
  if (/^Node-copyfrom-rev: [[:digit:]]+$/) {
    if (debug >= 1) {
      printf("[debug] %09d: found %s\n", NR, $0) > "/dev/stderr"
    }
    #
    nodecopyrev = gensub(/^Node-copyfrom-rev: /, "", 1, $0) + 0  ## addition forces number
    next
  }
  #
  if (/^Node-copyfrom-path: /) {
    if (debug >= 1) {
      printf("[debug] %09d: found %s\n", NR, $0) > "/dev/stderr"
    }
    #
    nodecopypath = gensub(/^Node-copyfrom-path: /, "", 1, $0)
    next
  }
  #
  next ## skip all other information
}


###
### Property Section
###
function processProperty() {
  if ((debug >= 3) || (debug >= 2 && property_key_relevant)) {
    printf("[debug] %09d: found %s property value for %s with content:\n%s\n", NR, process_properties, property_key, property_value) > "/dev/stderr"
  }
  #
  if (property_key == "svn:mergeinfo") {
    if (property_value && !(property_value in cross_branch_mergeinfos)) {
      cross_branch_mergeinfos[property_value] = revision
      #
      nodecopypath = gensub(/^(.+):.*$/, "\\1", 1, property_value)
      nodecopyrev = gensub(/^.*:.*([[:digit:]]+)$/, "\\1", 1, property_value)
      if (debug >= 2) {
        printf("[debug] %09d: PROCESSING mergeinfo %s (rev %s)\n", NR, nodecopypath, nodecopyrev) > "/dev/stderr"
      }
      processBranches("merge")
    }
  }
}

(process_properties) {
  if (/^PROPS-END$/) {  ## end of property section
    if (property_key_relevant) {
      processProperty()
    }
    clearPropertyVars()
    #
    process_properties = 0
    next
  }
  #
  ## handling property value (before key handling as next key marks the end of the value)
  if (property_stage == 2) {  ## check for value start and byte length
    if (/^V [[:digit:]]+$/) {
      property_stage++
      property_value_length = gensub(/^V /, "", 1, $0) + 0  ## addition forces number
      #
      if (debug >= 3) {
        printf("[debug] %09d: found %s property value start with length %s for %s\n", NR, process_properties, property_value_length, property_key) > "/dev/stderr"
      }
      #
      next
    } else {  ## undefined value
      clearPropertyVars()
    }
  } else if (property_stage == 3) {  ## check for value end or process value
    if (/^K [[:digit:]]+$/ || (/^D [[:digit:]]+$/)) {  ## next key = end of value
      if (property_key_relevant) {
        processProperty()
      }
      clearPropertyVars()
    } else {
      if (property_key_relevant) {
        if (property_key == "svn:mergeinfo") {  ## special case: process each merge entry separately
          if (property_value && /^\//) {
            processProperty()
            property_value = ""
          }
          property_value = property_value $0
        } else {  ## collect lines in property_value
          if (property_value) {
            property_value = property_value "\n"
          }
          property_value = property_value $0
        }  ## property_key
      }  ## property_key_relevant
      next
    }
  }  ## property_stage
  #
  ## handling property key
  if (property_stage == 0) {  ## check for key start and byte length
    if (/^K [[:digit:]]+$/ || /^D [[:digit:]]+$/) {
      property_stage++
      if (/^K /) {
        property_key_action = "define"
      } else if (/^D /) {
        property_key_action = "delete"
      }
      property_key_length = gensub(/^(K|D) /, "", 1, $0) + 0  ## addition forces number
      #
      if (debug >= 3) {
        printf("[debug] %09d: found %s property key start with action %s and length %s\n", NR, process_properties, property_key_action, property_key_length) > "/dev/stderr"
      }
      #
      next
    }
    #
    next ## skip all other information
  } else if (property_stage == 1) {  ## check property key
    property_key = $0
    #
    ## recognize relevant properties related to record type
    if (process_properties == "revision") {
q      ## none relevant
    } else if (process_properties == "nodepath") {
      if (/^svn:mergeinfo$/) {
        property_key_relevant = 1
      }
    }
    #
    if (property_key_action == "delete") {
      if (property_key_relevant) {
        processProperty()
      }
      clearPropertyVars()
    } else {
      property_stage++
    }
    #
    if ((debug >= 2) || (debug >= 1 && property_key_relevant)) {
      printf("[debug] %09d: found %s property key name %s\n", NR, process_properties, property_key) > "/dev/stderr"
    }
  }  ## property_stage
  #
  next ## skip all other information
}


###
### End of File
###
ENDFILE {
  foundrevs = length(cross_branch_copies)
  if (foundrevs == 0) {
    printf("=== %s: No revisions found with cross-branch svn copies\n", FILENAME)
  } else {
    if (csvsep) {
      backupofs=OFS
    }
    printf("=== %s: Found %i revisions with cross-branch svn copies\n", FILENAME, foundrevs)
    if (csvsep) {
      OFS=csvsep
      print("\"Revision\"", "\"Branch from\"", "\"Branch to\"")
      OFS=backupofs
    }
    PROCINFO["sorted_in"] = "@ind_num_asc"
    for (revision in cross_branch_copies) {
      if (!(csvsep)) {
        print(">>> Revision:", revision)
      }
      count = 0
      PROCINFO["sorted_in"] = "@ind_str_asc"
      for (branchfrom in cross_branch_copies[revision]) {
        for (branchto in cross_branch_copies[revision][branchfrom]) {
          if (csvsep) {
            csvrevision = revision
            csvbranchfrom = "\"" gensub(/"/, "\"\"", "g", branchfrom) "\""
            csvbranchto = "\"" gensub(/"/, "\"\"", "g", branchto) "\""
            OFS=csvsep
            print(csvrevision, csvbranchfrom, csvbranchto)
            OFS=backupofs
          } else {
            printf(" svn copy from \"%s\" to \"%s\"\n", branchfrom, branchto)
            if (details) {
              for (nodepath in cross_branch_copies[revision][branchfrom][branchto]) {
                count++
                printf("  %4i. \"%s\" (Revision %i) to \"%s\"\n", count, cross_branch_copies[revision][branchfrom][branchto][nodepath]["nodecopypath"], cross_branch_copies[revision][branchfrom][branchto][nodepath]["nodecopyrev"], nodepath)
              }  ## nodepath
            }  ## details
          }  ## csvsep
        }  ## branchto
      }  ## branchfrom
    }  ## revision
    #
    printf("--- %s: List of first revision of each cross-branch copy\n", FILENAME)
    PROCINFO["sorted_in"] = "@val_num_asc"
    if (csvsep) {
      OFS=csvsep
      print("\"Revision\"", "\"Branch from\"", "\"Branch to\"")
      OFS=backupofs
    }
    for (combined in cross_branch_copies_first) {  ## combined: branchfrom, branchto
      split(combined, separate, SUBSEP)
      if (csvsep) {
        csvrevision = cross_branch_copies_first[combined]
        csvbranchfrom = "\"" gensub(/"/, "\"\"", "g", separate[1]) "\""
        csvbranchto = "\"" gensub(/"/, "\"\"", "g", separate[2]) "\""
        OFS=csvsep
        print(csvrevision, csvbranchfrom, csvbranchto)
        OFS=backupofs
      } else {
        printf(" svn copy from \"%s\" to \"%s\" first in revision %i\n", separate[1], separate[2], cross_branch_copies_first[combined])
      }  ## csvsep
    }  ## combined
    #
    count = length(cross_branch_copies_first)
    printf("^^^ %s: Found %i revisions (unique %i) with cross-branch svn copies\n", FILENAME, foundrevs, count)
  }  ## foundrevs
}
