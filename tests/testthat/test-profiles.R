
test_that("library paths set in a user profile are overridden after load", {
  skip_on_cran()
  skip_on_os("windows")

  renv_tests_scope()

  init()
  renv_imbue_impl(project = getwd(), force = TRUE)

  profile <- c(
    ".libPaths('.')",
    "source('renv/activate.R')"
  )
  writeLines(profile, con = ".Rprofile")

  # ensure profile is executed
  renv_scope_envvars(R_PROFILE_USER = NULL)

  # invoke R
  args <- c("-s", "-e", shQuote("writeLines(.libPaths(), 'libpaths.txt')"))
  output <- system2(R(), args, stdout = FALSE, stderr = FALSE)

  actual <- readLines("libpaths.txt")
  expected <- renv_libpaths_all()

  expect_equal(actual[[1]], expected[[1]])

})

test_that(".First is executed; library paths are restored after", {

  skip_on_cran()
  skip_on_os("windows")

  renv_tests_scope()

  init()
  renv_imbue_impl(project = getwd(), force = TRUE)

  # add a .First to the profile
  profile <- quote({

    .First <- function() {
      writeLines("Hello from .First")
      .libPaths(".")
    }

    source("renv/activate.R")

  })

  # ensure profile is executed
  renv_scope_envvars(R_PROFILE_USER = NULL)
  writeLines(deparse(profile), con = ".Rprofile")

  # invoke R
  script <- renv_test_code({
    print(.libPaths())
    writeLines(.libPaths(), con = "libpaths.txt")
  })

  args <- c("-f", shQuote(script))
  output <- renv_system_exec(R(), args, action = "writing libpaths")

  actual <- readLines("libpaths.txt")
  expected <- renv_libpaths_all()

  expect_equal(actual[[1L]], expected[[1L]])

})
