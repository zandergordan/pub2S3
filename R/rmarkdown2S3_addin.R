#' Publish rmarkdown report to S3 bucket
#'
#' Call this function to render the active document, which must be a \code{.rmd}
#' document, and then copy the resulting \code{.html} and any \code{_files/} to
#' an S3 bucket. The user will be asked to enter the name of the S3 bucket they
#' want to copy to.
#'
#' @export
rmarkdown2S3_Addin <- function() {
  # Returns error if RStudio not available
  rstudioapi::verifyAvailable()

  # get path to active document
  rmd_path <- rstudioapi::getActiveDocumentContext()$path

  # verify that file extension is .rmd
  if (tools::file_ext(rmd_path) != "rmd") {
    stop("The active document is not an Rmarkdown file.")
  }

  # verify that the output type is html. Or is this really necessary? No reason
  # people can't put pdf's or .docs on their website. At the very least, the
  # aws.s3 code will need to be changed for other formats, as .html is currently
  # hard-coded

  # get the base name and directory of the file
  rmd_dir <- dirname(rmd_path)
  rmd_base <- tools::file_path_sans_ext(basename(rmd_path))


  # check for AWS S3 credentials. This can be from .Renviron, stored on local
  # keyring, or can be EC2 role. Currently I am just checking if any buckets
  # are available.
  available_buckets <- aws.s3::bucketlist()
  if (nrow(available_buckets) == 0) {
    stop("No S3 buckets are available, please check your AWS credentials.")
  }


  # assuming there is S3 access, ask the user which bucket they want to store
  # the html in. Remember which they choose for future reference.
  m <- "Please choose which of your available S3 buckets you wish to copy the report to:"
  user_bucket <- rstudioapi::showPrompt(
    title = "Select S3 Bucket",
    message = paste(c(m, available_buckets$Bucket), collapse = "\n"),
    default = rstudioapi::readPreference("rmarkdownS3_bucket", default = NULL)
  )
  # check if there is a valid bucket choice, then save preference using
  # rstudioapi::writePreference
  if (is.null(user_bucket)) stop("Please select an S3 bucket")
  if (!(user_bucket %in% available_buckets$Bucket)) {
    stop("Please provide the name of a valid S3 bucket you have access to.\n",
         "You can view a list of valid buckets with `aws.s3::bucketlist()`")
  }
  rstudioapi::writePreference("rmarkdownS3_bucket", user_bucket)

  # render the report
  xfun::Rscript_call(
    rmarkdown::render,
    list(input = rmd_path)
  )

  # With the desired bucket known, save the rendered report to S3
  aws.s3::put_object(file = file.path(rmd_dir, paste0(rmd_base, ".html")),
                     object = paste0(rmd_base, ".html"),
                     bucket = user_bucket,
                     show_progress = TRUE)
  # Check if a _files directory was made, and if so copy those files too
  extra_files_path <- file.path(rmd_dir, paste0(rmd_base, "_files"))
  if (dir.exists(extra_files_path)) {
    extra_files <- list.files(extra_files_path, recursive = TRUE)
    for (f in extra_files) {
      extra_file_name <- file.path(extra_files_path, f)
      extra_object_name <- file.path(paste0(rmd_base, "_files"), f)
      aws.s3::put_object(file = extra_file_name,
                         object = extra_object_name,
                         bucket = user_bucket,
                         show_progress = TRUE)
    }
  }
}
