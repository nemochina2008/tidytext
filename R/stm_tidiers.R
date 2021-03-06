#' Tidiers for Structural Topic Models from the stm package
#'
#' Tidy topic models fit by the stm package. The arguments and return values
#' are similar to \code{\link{lda_tidiers}}.
#'
#' @param x An STM fitted model object, created by \code{\link[stm]{stm}}.
#' @param matrix Whether to tidy the beta (per-term-per-topic, default)
#' or gamma/theta (per-document-per-topic) matrix. The stm package calls this
#' the theta matrix, but other topic modeling packages call this gamma.
#' @param data For \code{augment}, the data given to the stm function, either
#' as a \code{\link[quanteda]{dfm}} or as a tidied table with "document" and
#' "term" columns
#' @param log Whether beta/gamma/theta should be on a log scale, default FALSE
#' @param document_names Optional vector of document names for use with
#' per-document-per-topic tidying
#' @param ... Extra arguments, not used
#'
#' @return \code{tidy} returns a tidied version of either the beta or gamma matrix.
#'
#' @seealso \code{\link{lda_tidiers}}, \code{\link[stm]{stm}}
#'
#' If \code{matrix == "beta"} (default), returns a table with one row per topic and term,
#' with columns
#' \describe{
#'   \item{topic}{Topic, as an integer}
#'   \item{term}{Term}
#'   \item{beta}{Probability of a term generated from a topic according to
#'   the structural topic model}
#' }
#'
#' If \code{matrix == "gamma"}, returns a table with one row per topic and document,
#' with columns
#' \describe{
#'   \item{topic}{Topic, as an integer}
#'   \item{document}{Document name (if given in vector of \code{document_names}) or
#'   ID as an integer}
#'   \item{gamma}{Probability of topic given document}
#' }
#'
#' @examples
#'
#' \dontrun{
#' if (requireNamespace("stm", quietly = TRUE) && requireNamespace("quanteda", quietly = TRUE)) {
#'   library(dplyr)
#'   library(ggplot2)
#'   library(stm)
#'   library(quanteda)
#'
#'   inaug <- dfm(data_corpus_inaugural, remove = stopwords("english"), remove_punct = TRUE)
#'   topic_model <- stm(inaug, K = 3, verbose = FALSE, init.type = "Spectral")
#'
#'   # tidy the word-topic combinations
#'   td_beta <- tidy(topic_model)
#'   td_beta
#'
#'   # Examine the three topics
#'   td_beta %>%
#'     group_by(topic) %>%
#'     top_n(10, beta) %>%
#'     ungroup() %>%
#'     ggplot(aes(term, beta)) +
#'     geom_col() +
#'     facet_wrap(~ topic, scales = "free") +
#'     coord_flip()
#'
#'   # tidy the document-topic combinations, with optional document names
#'   td_gamma <- tidy(topic_model, matrix = "gamma",
#'                    document_names = rownames(inaug))
#'   td_gamma
#'
#'   # find the assignments of each word in each document
#'   assignments <- augment(topic_model, inaug)
#'   assignments
#' }
#' }
#'
#' @name stm_tidiers
#'
#' @export
tidy.STM <- function(x, matrix = c("beta", "gamma", "theta"), log = FALSE, document_names = NULL, ...) {
  matrix <- match.arg(matrix)
  if (matrix == "beta") {
    mat <- x$beta
  } else {
    mat <- x$theta
  }

  ret <- reshape2::melt(mat) %>%
    tbl_df()

  if (matrix == "beta") {
    ret <- transmute(ret, topic = Var1, term = x$vocab[Var2], beta = value)
  } else {
    ret <- transmute(ret, document = Var1, topic = Var2, gamma = value)
    if (!is.null(document_names)) {
      ret$document <- document_names[ret$document]
    }
  }

  if (matrix == "beta" && !log) {
    ret[[matrix]] <- exp(ret[[matrix]])
  } else if (matrix %in% c("gamma", "theta") && log) {
    ret[[matrix]] <- log(ret[[matrix]])
  }
  ret
}

#' @rdname stm_tidiers
#'
#' @return \code{augment} must be provided a data argument, either a
#' \code{\link[quanteda]{dfm}} or a table containing one row per original
#' document-term pair, such as is returned by \link{tdm_tidiers}, containing
#' columns \code{document} and \code{term}. It returns that same data as a table
#' with an additional column \code{.topic} with the topic assignment for that
#' document-term combination.
#'
#' @importFrom broom augment
#'
#' @export
augment.STM <- function(x, data, ...) {

  if (missing(data)) {
    stop("data argument must be provided in order to augment a stm model")
  }

  if (inherits(data, "data.frame") &&
      (all(c("document", "term") %in% colnames(data)))) {
    data$value <- 1
    mat <- cast_dfm(data, document, term, value)
  } else if (inherits(data, "dfm")) {
    mat <- data
    data <- tidy(mat)
  } else {
    stop("data argument must either be a dfm ",
         "(from quanteda) or a table with document and term columns")
  }

  beta <- t(as.matrix(x$beta$logbeta[[1]]))
  theta <- x$theta

  term_indices <- match(data$term, x$vocab)
  doc_indices <- match(data$document, rownames(mat))

  products <- beta[term_indices, ] * theta[doc_indices, ]
  keep <- !is.na(term_indices) & !is.na(doc_indices)

  data$.topic <- NA
  data$.topic[keep] <- apply(products[keep, ], 1, which.max)
  data
}

#' @rdname stm_tidiers
#'
#' @return \code{glance} always returns a one-row table, with columns
#' \describe{
#'   \item{k}{Number of topics in the model}
#'   \item{docs}{Number of documents in the model}
#'   \item{terms}{Number of terms in the model}
#'   \item{iter}{Number of iterations used}
#'   \item{alpha}{If an LDA model, the parameter of the Dirichlet distribution
#'   for topics over documents}
#' }
#'
#' @export

glance.STM <- function(x, ...) {
  ret <- data_frame(k = as.integer(x$settings$dim$K),
                    docs = x$settings$dim$N,
                    terms = x$settings$dim$V,
                    iter = length(x$convergence$bound),
                    alpha = x$settings$init$alpha)

  ret
}

#' @export
broom::augment
