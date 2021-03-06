#' Initialise a Handicap
#'
#' Initialise a handicap by splitting a dataframe of races up into groups of
#' similar class, then for each race in the group calculate a rating for the
#' winner using the remaining races in the group.  The result is a skeleton
#' handicap from which to start.
#'
#' @details Related to \link{zipf_race} and \link{zipf_hcp}, this function will
#' initialise a handicap.  It will split a dataframe of races into groups
#' according to \strong{group_by}, these groups should be races of similar class,
#' most (all) racing jurisdictions employ a type of classification. For each
#' race (identified by \strong{race_id}), in each group, the winner is assigned
#' a rating based on the other races in the same group.
#'
#' @return Returns a list consisting of:
#' \itemize{
#'      \item groups contains \strong{group_by} param
#'      \item race_id contains \strong{race_id} param
#'      \item counts dataframe of counts per group_by
#'      \item ratings dataframe of ratings (with 3 variables,
#'      \emph{group_by}, \emph{race_id}, and \emph{zipf_rtg})
#' }
#'
#' @param races dataframe of races
#' @param group_by name of variable(s) to group races found in
#' \strong{races}, eg. US races you wouldn't group claiming races and Stakes
#' races together, in UK you wouldn't group Class 4 and Listed races.
#' @param race_id name of variable to split \strong{races} up by
#' so each split is one race
#' @param btn_var name of variable in \strong{races} with margins
#' between horses
#' @param .progress plyr's progress bar (default = "none", options inc.
#' "text", "time", "tk" or "win")
#'
#' @export
zipf_init <- function(races, group_by, race_id, btn_var, .progress = "none") {

    # 1. Split races up according to group_by
    # 2. Split each group up by race_id, leaving an indiviual race
    # 3. Use zipf_hcp function and group_by split as past_races argument
    grouped_races <- plyr::dlply(races, group_by, .fun = function(group, race_id, btn_var) {

        plyr::ddply(group, race_id, .fun = function(race, group, race_id, btn_var) {

            c(zipf_rtg = zipf_hcp(race = race,
                     past_races = group,
                     race_id = race_id,
                     results = "simple",
                     btn_var = btn_var))
        },
        group = group,
        race_id = race_id,
        btn_var = btn_var,
        .progress = .progress)
    },
    race_id = race_id,
    btn_var = btn_var)

    # convert back into dataframe
    grouped_races <- plyr::ldply(grouped_races)

    # counts per group_by
    counts <- table(grouped_races[group_by])
    counts <- as.data.frame(counts)
    names(counts) <- c(group_by, "n")

    # begin constructing detailed list
    rcapper_output <- list()

    # assign a custom class to the list to allow S3 methods (see below)
    class(rcapper_output) <- "rcapper_zipf_init"

    rcapper_output$groups <- group_by
    rcapper_output$race_id <- race_id

    # table showing number of races in each
    rcapper_output$counts <- counts

    # dataframe of ratings
    rcapper_output$ratings <- grouped_races

    return(rcapper_output)
}

#' @export
print.rcapper_zipf_init <- function(x, ...) {

    object <- x
    n_races <- sum(object$counts$n)
    n_races <- paste("No. of races:\n\t", n_races, "\n")

    groups <- as.vector(object$counts[[object$groups]])
    groups <- paste(groups, collapse = ", ")
    groups <- paste("Race Groups:\n\t", groups, "\nCounts:")

    counts <- table(object$ratings[[object$groups]])

    cat("Initial handicap using zipf_init:\n\n")
    cat(n_races)
    cat(groups)
    print(counts)
    cat("\nRatings Summary:\n")
    print(summary(object$ratings$zipf_rtg))
}

#' @export
summary.rcapper_zipf_init <- function(object, ...) {

    n_races <- sum(object$counts$n)
    n_races <- paste("No. of races:\n\t", n_races, "\n")

    groups <- as.vector(object$counts[[object$groups]])
    groups <- paste(groups, collapse = ", ")
    groups <- paste("Race Groups:\n\t", groups, "\nCounts:")

    counts <- table(object$ratings[[object$groups]])

    cat("Initial handicap using zipf_init:\n\n")
    cat(n_races)
    cat(groups)
    print(counts)
    cat("\nRatings Summary:\n")
    print(summary(object$ratings$zipf_rtg))
}

#' @export
plot.rcapper_zipf_init <- function(x, ...) {

    object <- x
    # extract the dataframe, rename variables for plotting purposes,
    # dataframe should be minimum of 3 columns, however if user entered in two
    # or more variables into zipf_init (param group_by) then need to facet_wrap
    # the plot by these N variables
    df <- object$ratings

    # look at creating binwidths based on data
    # http://stats.stackexchange.com/questions/798/calculating-optimal-number-of-bins-in-a-histogram-for-n-where-n-ranges-from-30
    # bw <- diff(range(x)) / (2 * IQR(x) / length(x)^(1/3)))

    ggplot2::ggplot(df, ggplot2::aes(x = df$zipf_rtg)) +
        ggplot2::geom_histogram(ggplot2::aes(y = ..density..), binwidth = 1,
                                fill = "#d9220f", color = "#fcfcfc") +
        ggplot2::geom_density(fill = "#d8d8d8", alpha = .25) +
        ggplot2::labs(title = "zipf_init ratings") +
        ggplot2::facet_wrap(object$groups, scales = "free") +
        theme_rcapper()
}


#' Merge zipf_init to dataframe
#'
#' @description Take the list returned by \link{zipf_init} and the dataframe
#' entered into the \link{zipf_init} function, and merge them together,
#' returning a dataframe with ratings per runner.
#'
#' @param zipf_list list returned by \link{zipf_init}
#' @param races dataframe of races
#' @param btn_var name of variable in \strong{races} with margins
#' between horses, if entered it will calculate ratings for all losers using the
#' winners rating and subtracting \strong{btn_var}
#'
#' @export
merge_zipf_init <- function(zipf_list, races, btn_var = NULL) {

    if(class(zipf_list) != "rcapper_zipf_init") {
        stop("\"zipf_list\" is not an object of class \"rcapper_zipf_init\"")
    }

    ratings <- zipf_list$ratings
    mergeby <- c(zipf_list$race_id, zipf_list$groups)
    tmp <- merge(x = races, y = ratings, by = mergeby)

    # if user enters btn_var calculate ratings
    if(!is.null(btn_var)) {
        tmp$zipf_rtg <- tmp$zipf_rtg - tmp[[btn_var]]
        tmp$zipf_rtg <- round(tmp$zipf_rtg, 2)
    }

    return(tmp)
}
