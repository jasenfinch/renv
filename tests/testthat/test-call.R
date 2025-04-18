test_that("renv_call_matches() works as expected", {
  call <- quote(foo(1, 2))

  expect_true(renv_call_matches(call))
  expect_true(renv_call_matches(call, name = "foo"))
  expect_true(renv_call_matches(call, name = c("foo", "bar")))
  expect_true(renv_call_matches(call, n_args = 2))

  expect_false(renv_call_matches(call, "bar"))
  expect_false(renv_call_matches(call, n_args = 1))

  call <- quote(foo()(1, 2))
  expect_true(renv_call_matches(call))
  expect_false(renv_call_matches(call, "foo"))
})
