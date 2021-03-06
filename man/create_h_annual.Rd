% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utilities.R
\name{create_h_annual}
\alias{create_h_annual}
\title{Create Harvest Rate Annual}
\usage{
create_h_annual(h_step, y)
}
\arguments{
\item{h_step}{\code{\link[=numeric]{numeric()}} step harvest rate}

\item{y}{\code{\link[=integer]{integer()}} number of time steps in one year}
}
\value{
\code{\link[=numeric]{numeric()}}
}
\description{
Create Harvest Rate Annual
}
\examples{
create_h_annual(0.05, 1)
create_h_annual(0.01274146, 4)

}
