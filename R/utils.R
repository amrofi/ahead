# In alphabetical order

# create new predictors
create_new_predictors <- function(x,
                                  nb_hidden = 5,
                                  hidden_layer_bias = FALSE,
                                  method = c("sobol", "halton", "unif"),
                                  activ = c("relu", "sigmoid", "tanh",
                                            "leakyrelu", "elu", "linear"),
                                  a = 0.01,
                                  seed = 123)
{
  n <- nrow(x)

  if (nb_hidden > 0)
  {
    p <- ncol(x)
    method <- match.arg(method)

    # Activation function
    g <- switch(
      match.arg(activ),
      "relu" = function(x)
        x * (x > 0),
      "sigmoid" = function(x)
        1 / (1 + exp(-x)),
      "tanh" = function(x)
        tanh(x),
      "leakyrelu" = function(x)
        x * (x > 0) + a * x * (x <= 0),
      "elu" = function(x)
        x * (x >= 0) + a * (exp(x) - 1) * (x < 0),
      "linear" = function(x)
        x
    )

    if (hidden_layer_bias == FALSE)
    {
      # used for columns sample and for 'method == unif'
      set.seed(seed + 1)
      w <- remove_zero_cols(switch(
        method,
        "sobol" = 2 * t(randtoolbox::sobol(nb_hidden + 1, p)) - 1,
        "halton" = 2 * t(randtoolbox::halton(nb_hidden, p)) - 1,
        "unif" = matrix(
          runif(nb_hidden * p, min = -1, max = 1),
          nrow = p,
          ncol = nb_hidden
        )
      ))
      scaled_x <- my_scale(x)
      hidden_layer_obj <- remove_zero_cols(g(scaled_x$res %*% w),
                                           with_index = TRUE)
      hidden_layer <- hidden_layer_obj$mat

    } else { # hidden_layer_bias == TRUE
      pp <- p + 1
      # used for columns sample and for 'method == unif'
      set.seed(seed + 1)
      w <- remove_zero_cols(switch(
        method,
        "sobol" = 2 * t(randtoolbox::sobol(nb_hidden + 1, pp)) - 1,
        "halton" = 2 * t(randtoolbox::halton(nb_hidden, pp)) - 1,
        "unif" = matrix(
          runif(nb_hidden * pp, min = -1, max = 1),
          nrow = pp,
          ncol = nb_hidden
        )
      ))

      scaled_x <- my_scale(x)
      hidden_layer_obj <- remove_zero_cols(g(cbind(1, scaled_x$res) %*% w),
                                           with_index = TRUE)
      hidden_layer <- hidden_layer_obj$mat
    }

    res <- cbind(x, hidden_layer)
    nb_nodes <- ncol(hidden_layer)
    if (!is.null(nb_nodes))
      colnames(res) <- c(paste0("x", 1:p), # maybe use the real names
                         paste0("h", 1:nb_nodes))


    # if nb_hidden > 0 && (nb_predictors >= 2 && col_sample < 1)
    return(
      list(
        activ = g,
        xm = scaled_x$xm,
        xsd = scaled_x$xsd,
        w = w,
        predictors = res,
        hidden_layer_index = hidden_layer_obj$index
      )
    )
  } else {# if nb_hidden <= 0
    scaled_x <- my_scale(x)
    return(
      list(
        xm = scaled_x$xm,
        xsd = scaled_x$xsd,
        predictors = x,
        hidden_layer_index = hidden_layer_obj$index
      )
    )
  }
}


# Multivariate block boostrap
mbb <- function(r, n, b, seed=123)
{
  nT <- dim(r)[1]
  k <- dim(r)[2]

  freq_r <- stats::frequency(r)
  start_r <- stats::start(r)

  stopifnot(b > 1)

  # circular block bootstrap

  set.seed(seed)

  nb <- ceiling(n/b) # number of bootstrap reps
  js <- floor(runif(n = nb)*nT) # starting points - 1

  x <- matrix(NA, nrow = nb*b, ncol = k)

  for (i in 1:nb)
  {
    j <- ((js[i] + 1:b)%%nT) + 1 #positions in original data
    s <- (1:b) + (i-1)*b
    x[s, ] <- r[j, ]
  }

  if (nb*n > n) # correct length if nb*b > n
  {
    return(ts(drop(x[1:n,]), start = start_r, frequency = freq_r))
  }

  return(ts(drop(x), start = start_r, frequency = freq_r))
}


#  MASS::ginv
my_ginv <- function(X, tol = sqrt(.Machine$double.eps))
{
  if (length(dim(X)) > 2L || !(is.numeric(X) || is.complex(X)))
  {
    stop("'X' must be a numeric or complex matrix")
  }

  Xsvd <- La.svd(X)
  Positive <- Xsvd$d > max(tol * Xsvd$d[1L], 0)
  if (all(Positive))
  {
    return(crossprod(Xsvd$vt, (1/Xsvd$d * t(Xsvd$u))))
  }
  else if(!any(Positive))
  {
    return(array(0, dim(X)[2L:1L]))
  }
  else {
    return(crossprod(Xsvd$vt[, Positive, drop = FALSE], ((1/Xsvd$d[Positive]) *
                                                           t(Xsvd$u[, Positive, drop = FALSE]))))
  }
}
my_ginv <- compiler::cmpfun(my_ginv)


# scaling matrices
my_scale <- function(x, xm = NULL, xsd = NULL)
{
  rep_1_n <- rep.int(1, dim(x)[1])

  # centering and scaling, returning the means and sd's
  if(is.null(xm) && is.null(xsd))
  {
    xm <- colMeans(x)
    xsd <- my_sd(x)
    return(list(res = (x - tcrossprod(rep_1_n, xm))/tcrossprod(rep_1_n, xsd),
                xm = xm,
                xsd = xsd))
  }

  # centering and scaling
  if(is.numeric(xm) && is.numeric(xsd))
  {
    return((x - tcrossprod(rep_1_n, xm))/tcrossprod(rep_1_n, xsd))
  }

  # centering only
  if(is.numeric(xm) && is.null(xsd))
  {
    return(x - tcrossprod(rep_1_n, xm))
  }

  # scaling only
  if(is.null(xm) && is.numeric(xsd))
  {
    return(x/tcrossprod(rep_1_n, xsd))
  }
}
my_scale <- compiler::cmpfun(my_scale)


# calculate std's of columns
my_sd <- function(x)
{
  n <- dim(x)[1]
  return(drop(rep(1/(n-1), n) %*% (x - tcrossprod(rep.int(1, n), colMeans(x)))^2)^0.5)
}
my_sd <- compiler::cmpfun(my_sd)


# Ridge regression prediction
predict_myridge <- function(fit_obj, newx)
{
  my_scale(x = newx, xm = fit_obj$xm,
           xsd = fit_obj$scales)%*%fit_obj$coef + fit_obj$ym
}


# Remove_zero_cols
remove_zero_cols <- function(x, with_index = FALSE)
{
  if (with_index == FALSE)
  {
    return(x[, colSums(x == 0) != nrow(x)])
  } else {
    index <- colSums(x == 0) != nrow(x)
    return(list(mat = x[, index],
                index = index))
  }
}


# Scale a univariate time series
scale_ahead <- function(x, center = TRUE, scale = TRUE) {
  tspx <- tsp(x)
  x <- as.ts(scale.default(x, center = center, scale = scale))
  tsp(x) <- tspx
  return(x)
}
