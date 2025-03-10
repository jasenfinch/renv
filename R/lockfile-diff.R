
renv_lockfile_diff <- function(old, new, compare = NULL) {

  compare <- compare %||% function(lhs, rhs) {
    list(before = lhs, after = rhs)
  }

  # ensure both lists have the same names, inserting missing
  # entries for those without any value
  nms <- union(names(old), names(new)) %||% character()
  if (length(nms)) {

    nms <- sort(nms)
    old[renv_vector_diff(nms, names(old))] <- list(NULL)
    new[renv_vector_diff(nms, names(new))] <- list(NULL)

    old <- old[nms]
    new <- new[nms]

  }

  # ensure that these have the same length for comparison
  if (is.list(old) && is.list(new))
    length(old) <- length(new) <- max(length(old), length(new))

  # check for differences
  diffs <- mapply(
    renv_lockfile_diff_impl, old, new,
    MoreArgs = list(compare = compare),
    SIMPLIFY = FALSE
  )

  # drop NULL entries
  reject(diffs, empty)

}

renv_lockfile_diff_impl <- function(lhs, rhs, compare) {
  case(
    is.list(lhs) && empty(rhs)   ~ renv_lockfile_diff(lhs, list(), compare),
    empty(lhs) && is.list(rhs)   ~ renv_lockfile_diff(list(), rhs, compare),
    is.list(lhs) && is.list(rhs) ~ renv_lockfile_diff(lhs, rhs, compare),
    !identical(c(lhs), c(rhs))   ~ compare(lhs, rhs),
    NULL
  )
}

renv_lockfile_diff_record <- function(before, after) {

  before <- renv_record_normalize(before)
  after  <- renv_record_normalize(after)

  # first, compare on version / record existence
  type <- case(
    is.null(before) ~ "install",
    is.null(after)  ~ "remove",
    before$Version < after$Version ~ "upgrade",
    before$Version > after$Version ~ "downgrade"
  )

  if (!is.null(type))
    return(type)

  # check for a crossgrade -- where the package version is the same,
  # but details about the package's remotes have changed
  if (!setequal(renv_record_names(before), renv_record_names(after)))
    return("crossgrade")

  nm <- union(renv_record_names(before), renv_record_names(after))
  if (!identical(before[nm], after[nm]))
    return("crossgrade")

  NULL

}

renv_lockfile_diff_packages <- function(old, new) {

  old <- renv_lockfile_records(old)
  new <- renv_lockfile_records(new)

  packages <- named(union(names(old), names(new)))
  actions <- lapply(packages, function(package) {
    before <- old[[package]]; after <- new[[package]]
    renv_lockfile_diff_record(before, after)
  })

  Filter(Negate(is.null), actions)

}

renv_lockfile_override <- function(lockfile) {
  records <- renv_lockfile_records(lockfile)
  overrides <- renv_records_override(records)
  renv_lockfile_records(lockfile) <- overrides
  lockfile
}

renv_lockfile_repair <- function(lockfile) {

  records <- renv_lockfile_records(lockfile)

  # fix up records in lockfile
  renv_lockfile_records(lockfile) <- enumerate(records, function(package, record) {

    # if this package is from a repository, but doesn't specify an explicit
    # version, then use the latest-available version of that package
    source <- renv_record_source_normalize(record, record$Source)
    if (identical(source, "Repository") && is.null(record$Version)) {
      entry <- renv_available_packages_latest(package)
      record$Version <- entry$Version
    }

    # return normalized record
    record

  })

  lockfile

}
