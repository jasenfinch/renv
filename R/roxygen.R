
#' @param project The project directory. If `NULL`, then the active project will
#'   be used. If no project is currently active, then the current working
#'   directory is used instead.
#'
#' @param type The type of package to install ("source" or "binary"). Defaults
#'   to the value of `getOption("pkgType")`.
#'
#' @param lockfile Path to a lockfile. When `NULL` (the default), the
#'   `renv.lock` located in the root of the current project will be used.
#'
#' @param library The \R library to be used. When `NULL`, the active project
#'  library will be used instead.
#'
#' @param prompt Boolean; prompt the user before taking any action? For backwards
#'   compatibility, `confirm` is accepted as an alias for `prompt`.
#'
#' @param ... Unused arguments, reserved for future expansion. If any arguments
#'   are matched to `...`, renv will signal an error.
#'
#' @param clean Boolean; remove packages not recorded in the lockfile from
#'   the target library? Use `clean = TRUE` if you'd like the library state
#'   to exactly reflect the lockfile contents after `restore()`.
#'
#' @param rebuild Force packages to be rebuilt, thereby bypassing any installed
#'   versions of the package available in the cache? This can either be a
#'   boolean (indicating that all installed packages should be rebuilt), or a
#'   vector of package names indicating which packages should be rebuilt.
#'
#' @param repos The repositories to use when restoring packages installed
#'   from CRAN or a CRAN-like repository. By default, the repositories recorded
#'   in the lockfile will be, ensuring that (e.g.) CRAN packages are
#'   re-installed from the same CRAN mirror.
#'
#'   Use `repos = getOptions(repos)` to override with the repositories set
#'   in the current session, or see the `repos.override` option in [config] for
#'   an alternate way override.
#'
#' @param profile The profile to be activated. When `NULL`, the default
#'   profile is activated instead. See `vignette("profiles", package = "renv")`
#'   for more information.
#'
#' @param dependencies A vector of DESCRIPTION field names that should be used
#'   for package dependency resolution. When `NULL` (the default), the value
#'   of `renv::settings$package.dependency.fields` is used. The aliases
#'   "strong", "most", and "all" are also supported.
#'   See [tools::package_dependencies()] for more details.
#'
#' @return The project directory, invisibly. Note that this function is normally
#'   called for its side effects.
#'
#' @name renv-params
NULL

renv_roxygen_config_section <- function() {

  # read config
  config <- yaml::read_yaml("inst/config.yml")

  # generate items
  items <- map_chr(config, function(entry) {

    # extract fields
    name <- entry$name
    type <- entry$type
    default <- entry$default
    description <- entry$description

    # deparse default value
    default <- case(
      identical(default, list()) ~ "NULL",
      TRUE                       ~ deparse(default)
    )

    # generate table row
    fmt <- "\\subsection{renv.config.%s}{%s Defaults to \\code{%s}.}"
    sprintf(fmt, name, description, default)

  })

  c(
    "@section Configuration:",
    "",
    "The following renv configuration options are available:",
    "",
    items,
    ""
  )

}
