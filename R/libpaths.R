
the$libpaths <- new.env(parent = emptyenv())

# NOTE: if sandboxing is used then these symbols will be clobbered;
# save them so we can properly restore them later if so required
renv_libpaths_init <- function() {
  assign(".libPaths()",   .libPaths(),   envir = the$libpaths)
  assign(".Library",      .Library,      envir = the$libpaths)
  assign(".Library.site", .Library.site, envir = the$libpaths)
}

renv_libpaths_active <- function() {
  .libPaths()[[1L]]
}

renv_libpaths_all <- function() {
  .libPaths()
}

renv_libpaths_system <- function() {
  get(".Library", envir = the$libpaths)
}

renv_libpaths_site <- function() {
  get(".Library.site", envir = the$libpaths)
}

renv_libpaths_external <- function(project) {
  projlib <- settings$external.libraries(project = project)
  conflib <- config$external.libraries(project)
  .expand_R_libs_env_var(c(projlib, conflib))
}

# on Windows, attempting to use a library path containing
# characters considered special by cmd.exe will fail.
# to guard against this, we try to create a junction point
# from the temporary directory to the target library path
#
# https://github.com/rstudio/renv/issues/334
renv_libpaths_safe <- function(libpaths) {

  if (renv_libpaths_safe_check(libpaths))
    return(libpaths)

  map_chr(libpaths, renv_libpaths_safe_impl)

}

renv_libpaths_safe_check <- function(libpaths) {

  # if any of the paths have single quotes,
  # then we need to use a safe path
  # https://bugs.r-project.org/bugzilla/show_bug.cgi?id=17973
  if (any(grepl("'", libpaths, fixed = TRUE)))
    return(FALSE)

  # on Windows, we need to use safe library paths for R < 4.0.0
  # https://bugs.r-project.org/bugzilla/show_bug.cgi?id=17709
  if (renv_platform_windows() && getRversion() < "4.0.0")
    return(FALSE)

  # otherwise, we're okay
  return(TRUE)

}

renv_libpaths_safe_impl <- function(libpath) {

  # check for an unsafe library path
  unsafe <-
    Encoding(libpath) == "UTF-8" ||
    grepl("[&<>^|'\"]", libpath)

  # if the path appears safe, use it as-is
  if (!unsafe)
    return(libpath)

  # try to form a safe library path
  methods <- c(
    renv_libpaths_safe_tempdir,
    renv_libpaths_safe_userlib
  )

  for (method in methods) {
    safelib <- catchall(method(libpath))
    if (is.character(safelib))
      return(safelib)
  }

  # could not form a safe library path;
  # just use the existing library path as-is
  libpath

}

renv_libpaths_safe_tempdir <- function(libpath) {
  safelib <- tempfile("renv-safelib-")

  if (renv_platform_windows())
    renv_file_junction(libpath, safelib)
  else
    file.symlink(libpath, safelib)

  safelib
}

renv_libpaths_safe_userlib <- function(libpath) {

  # form path into user library
  userlib <- renv_libpaths_user()[[1]]
  base <- file.path(userlib, ".renv-links")
  ensure_directory(base)

  # create name for actual junction point
  name <- renv_hash_text(libpath)
  safelib <- file.path(base, name)

  # if the junction already exists, use it
  if (renv_file_same(libpath, safelib))
    return(safelib)

  # otherwise, try to create it. note that junction
  # points can be removed with a non-recursive unlink
  unlink(safelib)

  if (renv_platform_windows())
    renv_file_junction(libpath, safelib)
  else
    file.symlink(libpath, safelib)

  safelib

}

renv_libpaths_set <- function(libpaths) {
  oldlibpaths <- .libPaths()
  safepaths <- renv_libpaths_safe(libpaths)
  .libPaths(safepaths)
  oldlibpaths
}

renv_libpaths_default <- function() {
  the$libpaths$`.libPaths()`
}

# NOTE: may return more than one library path!
renv_libpaths_user <- function() {

  # if renv is active, the user library will be saved
  envvars <- c("RENV_DEFAULT_R_LIBS_USER", "R_LIBS_USER")
  for (envvar in envvars) {

    value <- Sys.getenv(envvar, unset = NA)
    if (is.na(value) || value %in% c("", "<NA>", "NULL"))
      next

    parts <- strsplit(value, .Platform$path.sep, fixed = TRUE)[[1L]]
    return(parts)

  }

  # otherwise, default to active library
  # (shouldn't happen but best be safe)
  renv_libpaths_active()

}

renv_init_libpaths <- function(project) {

  projlib <- renv_paths_library(project = project)
  extlib <- renv_libpaths_external(project = project)
  userlib <- if (config$user.library())
    renv_libpaths_user()

  libpaths <- c(projlib, extlib, userlib)
  lapply(libpaths, ensure_directory)

  libpaths

}

renv_libpaths_restore <- function() {
  libpaths <- get(".libPaths()", envir = the$libpaths)
  renv_libpaths_set(libpaths)
}

# We need to ensure the system library is included, for cases where users have
# provided an explicit 'library' argument in calls to functions like
# 'renv::restore(library = <...>)')
#
# https://github.com/rstudio/renv/issues/1544
renv_libpaths_resolve <- function(library = NULL) {

  if (is.null(library))
    return(renv_libpaths_all())

  unique(c(library, .Library))

}
