
R <- function() {
  bin <- normalizePath(R.home("bin"), winslash = "/")
  exe <- if (renv_platform_windows()) "R.exe" else "R"
  file.path(bin, exe)
}

r <- function(args, ...) {

  # ensure R_LIBS is set; unset R_LIBS_USER and R_LIBS_SITE
  # so that R_LIBS will always take precedence
  rlibs <- paste(renv_libpaths_all(), collapse = .Platform$path.sep)
  renv_scope_envvars(R_LIBS = rlibs, R_LIBS_USER = "NULL", R_LIBS_SITE = "NULL")

  # ensure Rtools is on the PATH for Windows
  renv_scope_rtools()

  # invoke r
  suppressWarnings(system2(R(), args, ...))

}

r_exec_error <- function(package, output, label, extra) {

  # installation failed; write output for user
  fmt <- "Error %sing package '%s':"
  header <- sprintf(fmt, label, package)

  lines <- paste(rep("=", nchar(header)), collapse = "")

  # try to add diagnostic information if possible
  diagnostics <- r_exec_error_diagnostics(package, output)
  if (!empty(diagnostics)) {
    size <- min(getOption("width"), 78L)
    dividers <- paste(rep.int("-", size), collapse = "")
    output <- c(output, paste(dividers, diagnostics, collapse = "\n\n"))
  }

  # normalize 'extra'
  extra <- if (is.integer(extra))
    paste("error code", extra)
  else
    paste(renv_path_pretty(extra), "does not exist")

  # stop with an error
  footer <- sprintf("%s of package '%s' failed [%s]", label, package, extra)
  all <- c(header, lines, "", output, footer)
  abort(all)

}

r_exec_error_diagnostics_fortran_library <- function() {

  checker <- function(output) {
    pattern <- "library not found for -l(quadmath|gfortran|fortran)"
    idx <- grep(pattern, output, ignore.case = TRUE)
    if (length(idx))
      return(unique(output[idx]))
  }

  suggestion <- "
R was unable to find one or more FORTRAN libraries during compilation.
This often implies that the FORTRAN compiler has not been properly configured.
Please see https://stackoverflow.com/q/35999874 for more information.
"

  list(
    checker = checker,
    suggestion = suggestion
  )

}

r_exec_error_diagnostics_fortran_binary <- function() {

  checker <- function(output) {
    pattern <- "gfortran: no such file or directory"
    idx <- grep(pattern, output, ignore.case = TRUE)
    if (length(idx))
      return(unique(output[idx]))
  }

  suggestion <- "
R was unable to find the gfortran binary.
gfortran is required for the compilation of FORTRAN source files.
Please check that gfortran is installed and available on the PATH.
Please see https://stackoverflow.com/q/35999874 for more information.
"

  list(
    checker = checker,
    suggestion = suggestion
  )

}

r_exec_error_diagnostics_openmp <- function() {

  checker <- function(output) {
    pattern <- "unsupported option '-fopenmp'"
    idx <- grep(pattern, output, fixed = TRUE)
    if (length(idx))
      return(unique(output[idx]))
  }

  suggestion <- "
R is currently configured to use a compiler that does not have OpenMP support.
You may need to disable OpenMP, or update your compiler toolchain.
Please see https://support.bioconductor.org/p/119536/ for a related discussion.
"

  list(
    checker = checker,
    suggestion = suggestion
  )

}

r_exec_error_diagnostics <- function(package, output) {

  diagnostics <- list(
    r_exec_error_diagnostics_fortran_library(),
    r_exec_error_diagnostics_fortran_binary(),
    r_exec_error_diagnostics_openmp()
  )

  suggestions <- uapply(diagnostics, function(diagnostic) {

    check <- catch(diagnostic$checker(output))
    if (!is.character(check))
      return()

    suggestion <- diagnostics$suggestion
    reasons <- paste("-", shQuote(check), collapse = "\n")
    paste(diagnostic$suggestion, "Reason(s):", reasons, sep = "\n")

  })

  as.character(suggestions)

}

# install package called 'package' located at path 'path'
r_cmd_install <- function(package, path, ...) {

  # normalize path to package
  path <- renv_path_normalize(path, mustWork = TRUE)

  # unpack .zip source archives before install
  # https://github.com/rstudio/renv/issues/1359
  ftype <- renv_file_type(path)
  atype <- renv_archive_type(path)
  ptype <- renv_package_type(path)

  unpack <-
    ftype == "file" &&
    atype == "zip" &&
    ptype == "source"

  if (unpack) {
    newpath <- renv_package_unpack(package, path, force = TRUE)
    if (!identical(newpath, path)) {
      path <- newpath
      defer(unlink(path, recursive = TRUE))
    }
  }

  # rename binary .zip files if necessary
  rename <-
    ftype == "file" &&
    atype == "zip" &&
    ptype == "binary"

  if (rename) {
    regexps <- .standard_regexps()
    fmt <- "^%s(?:_%s)?\\.zip$"
    pattern <- sprintf(fmt, regexps$valid_package_name, regexps$valid_package_version)
    if (!grepl(pattern, basename(path), perl = TRUE)) {
      dir <- renv_scope_tempfile(package)
      ensure_directory(dir)
      newpath <- file.path(dir, paste(package, "zip", sep = "."))
      renv_file_copy(path, newpath)
      path <- newpath
    }
  }

  # resolve default library path
  library <- renv_libpaths_active()

  # validate that we have command line tools installed and
  # available for e.g. macOS
  if (renv_platform_macos() && renv_package_type(path) == "source")
    renv_xcode_check()

  # perform platform-specific pre-install checks
  renv_scope_install()

  # perform the install
  # note that we need to supply '-l' below as otherwise the library paths
  # could be changed by, for example, site-specific profiles
  args <- c(
    "--vanilla",
    "CMD", "INSTALL", "--preclean", "--no-multiarch", "--with-keep.source",
    r_cmd_install_option(package, "configure.args", TRUE),
    r_cmd_install_option(package, "configure.vars", TRUE),
    r_cmd_install_option(package, c("install.opts", "INSTALL_opts"), FALSE),
    "-l", renv_shell_path(library),
    ...,
    renv_shell_path(path)
  )

  if (config$install.verbose()) {

    status <- r(args, stdout = "", stderr = "")
    if (!identical(status, 0L))
      stopf("install of package '%s' failed", package)

    installpath <- file.path(library, package)
    if (!file.exists(installpath)) {
      fmt <- "install of package '%s' failed: %s does not exist"
      stopf(fmt, package, renv_path_pretty(installpath))
    }

    installpath

  } else {

    output <- r(args, stdout = TRUE, stderr = TRUE)
    status <- attr(output, "status") %||% 0L
    if (!identical(status, 0L))
      r_exec_error(package, output, "install", status)

    installpath <- file.path(library, package)
    if (!file.exists(installpath))
      r_exec_error(package, output, "install", installpath)

    installpath

  }


}

r_cmd_build <- function(package, path, ...) {

  path <- renv_path_normalize(path, mustWork = TRUE)
  args <- c("--vanilla", "CMD", "build", "--md5", ..., renv_shell_path(path))

  output <- r(args, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  if (!identical(status, 0L))
    r_exec_error(package, output, "build", status)

  pasted <- paste(output, collapse = "\n")
  pattern <- "[*] building .([a-zA-Z0-9_.-]+)."
  matches <- regexec(pattern, pasted)
  text <- regmatches(pasted, matches)

  tarball <- text[[1L]][[2L]]
  if (!file.exists(tarball))
    r_exec_error(package, output, "build", tarball)

  file.path(getwd(), tarball)

}

r_cmd_install_option <- function(package, options, configure) {

  # read option -- first, check for package-specific option, then
  # fall back to 'global' option
  for (option in options) {
    value <- r_cmd_install_option_impl(package, option, configure)
    if (!is.null(value))
      return(value)
  }

}

r_cmd_install_option_impl <- function(package, option, configure) {

  value <-
    getOption(paste(option, package, sep = ".")) %||%
    getOption(option)

  if (is.null(value))
    return(NULL)

  # if the value is named, treat it as a list,
  # mapping package names to their configure arguments
  if (!is.null(names(value)))
    value <- as.list(value)

  # check for named values
  if (!is.null(names(value))) {
    value <- value[[package]]
    if (is.null(value))
      return(NULL)
  }

  # if this is a configure option, format specially
  if (configure) {
    confkey <- sub(".", "-", option, fixed = TRUE)
    confval <- if (!is.null(names(value)))
      shQuote(paste(names(value), value, sep = "=", collapse = " "))
    else
      shQuote(paste(value, collapse = " "))
    return(sprintf("--%s=%s", confkey, confval))
  }

  # otherwise, just paste it
  paste(value, collapse = " ")

}

r_cmd_config <- function(...) {

  renv_system_exec(
    command = R(),
    args    = c("--vanilla", "CMD", "config", ...),
    action  = "reading R CMD config"
  )

}
