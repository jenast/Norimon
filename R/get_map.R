#' Get map of terrestrial norway
#'
#' @param region_subset Optional character vector of regions to subset.
#'
#' @return An sf-object of the terrestrial landmass of Norway, contingent on region subset.
#' @export
#'
#'
#'
#' @examples
#'
#'
#' \dontrun{
#'
#'    norway <- get_map()
#'
#'norway <- norway %>%
#'  left_join(beetle_shannon_boot,
#'            by = c("region" = "region_name")) %>%
#'  replace_na(list(year =  2021))
#'
#'
#' norway %>%
#'  filter(year == 2021) %>%
#'  ggplot() +
#'  geom_sf(aes(fill = boot_mean)) +
#'  scale_fill_nina(name = "Beetle Shannon diversity",
#'                  discrete = FALSE)
#'
#'
#' }
#'
#'
#'

get_map <- function(region_subset = NULL){

  norway_terr <- sf::read_sf(con,
                             layer = DBI::Id(schema = "backgrounds", table = "norway_terrestrial")) %>%
    select(fylke = navn)


    region_def <- tibble(region = c("Trøndelag",
                                         "Østlandet",
                                         "Østlandet",
                                         "Østlandet",
                                         "Østlandet",
                                         "Sørlandet",
                                         "Sørlandet",
                                         "Vestlandet",
                                         "Vestlandet",
                                         "Nord-Norge",
                                         "Nord-Norge"),
                         fylke = c("Trøndelag",
                                        "Innlandet",
                                        "Oslo",
                                        "Vestfold og Telemark",
                                        "Viken",
                                        "Rogaland",
                                        "Agder",
                                        "Vestland",
                                        "Møre og Romsdal",
                                        "Troms og Finnmark",
                                        "Nordland"))

    norway_terr <- norway_terr %>%
      left_join(region_def,
           by = c("fylke" = "fylke"))

    if(!is.null(region_subset)){

      norway_terr <- norway_terr %>%
      filter(region %in% region_subset)

  }

  return(norway_terr)

}


