
renv_json_read <- function(file = NULL, text = NULL) {

  jlerr <- NULL

  # if jsonlite is loaded, use that instead
  if ("jsonlite" %in% loadedNamespaces()) {

    json <- catch(renv_json_read_jsonlite(file, text))
    if (!inherits(json, "error"))
      return(json)

    jlerr <- json

  }

  # otherwise, fall back to the default JSON reader
  json <- catch(renv_json_read_default(file, text))
  if (!inherits(json, "error"))
    return(json)

  # report an error
  if (!is.null(jlerr))
    stop(jlerr)
  else
    stop(json)

}

renv_json_read_jsonlite <- function(file = NULL, text = NULL) {
  text <- paste(text %||% read(file), collapse = "\n")
  jsonlite::fromJSON(txt = text, simplifyVector = FALSE)
}

renv_json_read_default <- function(file = NULL, text = NULL) {

  # find strings in the JSON
  text <- paste(text %||% read(file), collapse = "\n")
  pattern <- '["](?:(?:\\\\.)|(?:[^"\\\\]))*?["]'
  locs <- gregexpr(pattern, text, perl = TRUE)[[1]]

  # if any are found, replace them with placeholders
  replaced <- text
  strings <- character()
  replacements <- character()

  if (!identical(c(locs), -1L)) {

    # get the string values
    starts <- locs
    ends <- locs + attr(locs, "match.length") - 1L
    strings <- substring(text, starts, ends)

    # only keep those requiring escaping
    strings <- grep("[[\\]{}:]", strings, perl = TRUE, value = TRUE)

    # compute replacements
    replacements <- sprintf('"\032%i\032"', seq_along(strings))

    # replace the strings
    mapply(function(string, replacement) {
      replaced <<- sub(string, replacement, replaced, fixed = TRUE)
    }, strings, replacements)

  }

  # transform the JSON into something the R parser understands
  transformed <- replaced
  transformed <- gsub("{}", "`names<-`(list(), character())", transformed, fixed = TRUE)
  transformed <- gsub("[[{]", "list(", transformed, perl = TRUE)
  transformed <- gsub("[]}]", ")", transformed, perl = TRUE)
  transformed <- gsub(":", "=", transformed, fixed = TRUE)
  text <- paste(transformed, collapse = "\n")

  # parse it
  json <- parse(text = text, keep.source = FALSE, srcfile = NULL)[[1L]]

  # construct map between source strings, replaced strings
  map <- as.character(parse(text = strings))
  names(map) <- as.character(parse(text = replacements))

  # convert to list
  map <- as.list(map)

  # remap strings in object
  remapped <- renv_json_remap(json, map)

  # evaluate
  eval(remapped, envir = baseenv())

}

renv_json_remap <- function(json, map) {

  # fix names
  if (!is.null(names(json))) {
    lhs <- match(names(json), names(map), nomatch = 0L)
    rhs <- match(names(map), names(json), nomatch = 0L)
    names(json)[rhs] <- map[lhs]
  }

  # fix values
  if (is.character(json))
    return(map[[json]] %||% json)

  # handle true, false, null
  if (is.name(json)) {
    text <- as.character(json)
    if (text == "true")
      return(TRUE)
    else if (text == "false")
      return(FALSE)
    else if (text == "null")
      return(NULL)
  }

  # recurse
  if (is.recursive(json)) {
    for (i in seq_along(json)) {
      json[i] <- list(renv_json_remap(json[[i]], map))
    }
  }

  json

}
