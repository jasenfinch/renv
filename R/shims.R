
the$shims <- new.env(parent = emptyenv())

renv_shim_install_packages <- function(pkgs, ...) {

  # place Rtools on PATH
  renv_scope_rtools()

  # currently we only handle the case where only 'pkgs' was specified
  if (missing(pkgs) || nargs() != 1) {
    call <- sys.call()
    call[[1L]] <- quote(utils::install.packages)
    return(eval(call, envir = parent.frame()))
  }

  # otherwise, we get to handle it
  install(pkgs)

}

renv_shim_update_packages <- function(lib.loc = NULL, ...) {

  # handle only 0-argument case
  if (nargs() != 0) {
    call <- sys.call()
    call[[1L]] <- quote(utils::update.packages)
    return(eval(call, envir = parent.frame()))
  }

  update(library = lib.loc)

}

renv_shim_remove_packages <- function(pkgs, lib) {

  # handle single-argument case
  if (nargs() != 1) {
    call <- sys.call()
    call[[1L]] <- quote(utils::remove.packages)
    return(eval(call, envir = parent.frame()))
  }

  remove(pkgs)

}

renv_shim_create <- function(shim, sham) {
  formals(shim) <- formals(sham)
  shim
}

renv_shims_enabled <- function(project) {
  config$shims.enabled()
}

renv_shims_activate <- function() {

  renv_shims_deactivate()

  install_shim <- renv_shim_create(renv_shim_install_packages, utils::install.packages)
  assign("install.packages", install_shim, envir = the$shims)

  update_shim <- renv_shim_create(renv_shim_update_packages, utils::update.packages)
  assign("update.packages", update_shim, envir = the$shims)

  remove_shim <- renv_shim_create(renv_shim_remove_packages, utils::remove.packages)
  assign("remove.packages", remove_shim, envir = the$shims)

  args <- list(the$shims, name = "renv:shims", warn.conflicts = FALSE)
  do.call(base::attach, args)

}

renv_shims_deactivate <- function() {
  while ("renv:shims" %in% search())
    detach("renv:shims")
}
