#' obs_from_db Get insect observation data from the database
#'
#' @param id_type Type of identification type. Defaults to metabarcoding data
#' @param subset_orders Optional subset of order
#' @param subset_families Optional subset of families
#' @param subset_genus Optional subset of genus
#' @param subset_species Optional subset of species
#' @param subset_year Optional subset of year
#' @param subset_region Optional subset of region
#' @param trap_type Optional subset of trap type
#' @param limit Optional limit the output to number of rows (for testing)
#' @param dataset Choose the dataset to fetch data from. Default "NasIns" for national insect monitoring data
#' @param agg_level Aggregation level of data. "year_locality", "region_habitat", "region_habitat_year", "total". Default to year_locality
#' @param as_tibble Coerce output to class tibble
#'
#' @return A tibble of insect observations from the database
#' @export
#'
#' @examples
#'
#' dontrun{
#'
#'   source("~/.rpgpass")
#'
#'   connect_to_database(
#'      username = username,
#'      password = password
#'   )
#'
#'   rm(list = c("username", "password"))
#'
#'
#'   beetles_2022 <- obs_from_db(subset_orders = "Coleoptera",
#'                               agg_level = "year_locality")
#'
#' }
#'
#'
#'



obs_from_db <- function(id_type = c("metabarcoding"),
                        subset_orders = NULL,
                        subset_families = NULL,
                        subset_genus = NULL,
                        subset_species = NULL,
                        subset_year = NULL,
                        subset_region = NULL,
                        trap_type = "All",
                        limit = NULL,
                        dataset = "NasIns",
                        agg_level = "year_locality",
                        as_tibble = F){

  checkCon()

  if(!is.null(subset_region)){
  subset_region <- match.arg(subset_region, choices = c("Østlandet", "Trøndelag"))
  }

  id_type <- match.arg(id_type, choices = c("metabarcoding"))
  dataset <- match.arg(dataset, choices = c("NasIns",
                                            "OkoTrond",
                                            "TidVar",
                                            "Nerlandsøya"))

  agg_level <- match.arg(agg_level, choices = c("year_locality",
                                                "locality_sampling",
                                                "region_habitat",
                                                "region_habitat_year",
                                                "total",
                                                "none"))

  trap_type <- match.arg(trap_type,
                         choices = c("All", "MF", "VF", NULL))


  ##Set up table sources
  ##Probably needs updating after new batch of data. Also need to test filtering of different identification types
  observations <- dplyr::tbl(con, dbplyr::in_schema("occurrences", "observations"))
  identifications <- dplyr::tbl(con, dbplyr::in_schema("events", "identifications"))
  sampling_trap <- dplyr::tbl(con, dbplyr::in_schema("events", "sampling_trap"))
  locality_sampling <- dplyr::tbl(con, dbplyr::in_schema("events", "locality_sampling"))
  year_locality <- dplyr::tbl(con, dbplyr::in_schema("events", "year_locality"))
  localities <- dplyr::tbl(con, dbplyr::in_schema("locations", "localities"))
  identification_techniques <- dplyr::tbl(con, dbplyr::in_schema("lookup", "identification_techniques"))
  traps <- dplyr::tbl(con, dbplyr::in_schema("locations", "traps"))

  ##Join the tables

  joined <- observations %>%
    left_join(identifications,
              by = c("identification_id" = "id"),
              suffix = c("_obs", "_ids")) %>%
    left_join(identification_techniques,
              by = c("identification_name", "identification_name"),
              suffix = c("_obs", "_idtechn")) %>%
    left_join(sampling_trap,
              by = c("sampling_trap_id" = "id"),
              suffix = c("_obs", "_st")) %>%
    left_join(locality_sampling,
              by = c("locality_sampling_id" = "id"),
              suffix = c("_obs", "_ls")) %>%
    left_join(year_locality,
              by = c("year_locality_id" = "id"),
              suffix = c("_obs", "_yl")) %>%
    left_join(localities,
              by = c("locality_id" = "id"),
              suffix = c("_obs", "_loc"))  %>%
    left_join(traps,
              by = c("trap_id" = "id",
                     "year" = "year",
                     "locality" = "locality")
    ) %>%
    mutate(year = as.character(year))



  ##Exclude 2020 4 week samplings

  joined <-  joined %>%
    mutate(weeks_sampled = ifelse(grepl("2020", year) & (grepl("1", trap_short_name) | grepl("3", trap_short_name)), 2, 4)) %>%
    mutate(weeks_sampled = ifelse(grepl("2020", year), weeks_sampled, 2))

  joined <- joined %>%
    filter(weeks_sampled == 2)


  if(id_type == "metabarcoding"){
    joined <- joined %>%
      filter(identification_type == "metabarcoding")
  }

  #Filter on region name
  if(!is.null(subset_region)){
    subset_region <- c("", subset_region)
    joined <- joined %>%
      filter(region_name %IN% subset_region)
  }

  if(!is.null(subset_orders)){
    subset_orders <- c("", subset_orders) #To allow one-length subsets
    joined <- joined %>%
      filter(id_order %IN% subset_orders)
  }

  if(!is.null(subset_families)){
    subset_families <- c("", subset_families)
    joined <- joined %>%
      filter(id_family %IN% subset_families)
  }

  if(!is.null(subset_species)){
    subset_species <- c("", subset_species)
    joined <- joined %>%
      filter(species_latin_fixed %in% subset_species)
  }

  if(!is.null(subset_year)){
    subset_year <- c("", subset_year)
    joined <- joined %>%
      filter(year %IN% subset_year)
  }

  if(!is.null(subset_genus)){
    subset_genus <- c("", subset_genus)
    joined <- joined %>%
      filter(id_genus %IN% subset_genus)
  }

  #filter on dataset

  if(!is.null(dataset)){
    joined <- joined %>%
      filter(project_short_name == dataset)
  }

  #filter on trap type (recommended to only take MF)
  if(!is.null(trap_type) & trap_type != "All"){
    joined <- joined %>%
      filter(grepl((trap_type), sample_name))
  }


  ##Aggregate data to choosen level
  ##Add more choices?

  res <- joined


  ##This is slow because we have to collect the data before we calculate Shannon index.
  ##Best would be to do the Shannon calc on the database side. Seems harder than I first thought.
  if(agg_level == "year_locality"){

    res <- res %>%
      collect() %>%
      group_by(year_locality_id, locality_id, species_latin_fixed) %>%
      summarise(no_asv_per_species = n_distinct(sequence_id)) %>%
      group_by(year_locality_id, locality_id) %>%
      summarise(no_species = n_distinct(species_latin_fixed),
                shannon_div = calc_shannon(species_latin_fixed),
                mean_asv_per_species = mean(no_asv_per_species)) %>%
      left_join(localities,
                by = c("locality_id" = "id"),
                copy = T) %>%
      left_join(year_locality,
                by = c("year_locality_id" = "id",
                       "locality_id" = "locality_id",
                       "ano_flate_id" = "ano_flate_id",
                       "ssbid" = "ssbid"),
                copy = T) %>%
      ungroup() %>%
      select(year,
             locality,
             habitat_type,
             region_name,
             no_species,
             shannon_div,
             mean_asv_per_species) %>%
      arrange(year,
              region_name,
              habitat_type,
              locality)

  }


  if(agg_level == "locality_sampling"){

    res <- res %>%
      collect() %>%
      group_by(start_date_obs, end_date_obs, sampling_name, year_locality_id, locality_id, species_latin_fixed) %>%
      summarise(no_asv_per_species = n_distinct(sequence_id)) %>%
      group_by(sampling_name, year_locality_id, locality_id) %>%
      summarise(no_trap_days = mean(as.numeric(end_date_obs - start_date_obs)), ##to get the mean trap days from all traps within the sampling event (should be the same for all traps)
                no_species = n_distinct(species_latin_fixed),
                shannon_div = calc_shannon(species_latin_fixed),
                mean_asv_per_species = mean(no_asv_per_species)) %>%
      left_join(localities,
                by = c("locality_id" = "id"),
                copy = T) %>%
      left_join(year_locality,
                by = c("year_locality_id" = "id"),
                copy = T) %>%
      ungroup() %>%
      select(year,
             locality,
             sampling_name,
             habitat_type,
             region_name,
             no_trap_days,
             no_species,
             shannon_div,
             mean_asv_per_species) %>%
      arrange(year,
              region_name,
              habitat_type,
              locality,
              sampling_name)

  }

  if(agg_level == "region_habitat"){

    res <- res %>%
      collect() %>%
      group_by(region_name,
               habitat_type,
               species_latin_fixed) %>%
      summarise(no_asv_per_species = n_distinct(sequence_id)) %>%
      group_by(region_name,
               habitat_type) %>%
      summarise(no_species = n_distinct(species_latin_fixed),
                shannon_div = calc_shannon(species_latin_fixed),
                mean_asv_per_species = mean(no_asv_per_species)) %>%
      ungroup() %>%
      select(habitat_type,
             region_name,
             no_species,
             shannon_div,
             mean_asv_per_species) %>%
      arrange(habitat_type,
              region_name)

  }


  if(agg_level == "region_habitat_year"){

    res <- res %>%
      collect() %>%
      group_by(region_name,
               habitat_type,
               year,
               species_latin_fixed) %>%
      summarise(no_asv_per_species = n_distinct(sequence_id)) %>%
      group_by(region_name,
               habitat_type,
               year) %>%
      summarise(no_species = n_distinct(species_latin_fixed),
                shannon_div = calc_shannon(species_latin_fixed),
                mean_asv_per_species = mean(no_asv_per_species)) %>%
      ungroup() %>%
      select(year,
             habitat_type,
             region_name,
             no_species,
             shannon_div,
             mean_asv_per_species) %>%
      arrange(year,
              habitat_type,
              region_name
      )

  }

  if(agg_level == "total"){

    res <- res %>%
      collect() %>%
      group_by(species_latin_fixed) %>%
      summarise(no_asv_per_species = n_distinct(sequence_id)) %>%
      summarise(no_species = n_distinct(species_latin_fixed),
                shannon_div = calc_shannon(species_latin_fixed),
                mean_asv_per_species = mean(no_asv_per_species)) %>%
      ungroup() %>%
      select(no_species,
             shannon_div,
             mean_asv_per_species)


  }



  if(!is.null(limit)){
    res <- joined %>%
      head(limit)
  }

  if(as_tibble){
    res <- res %>%
      as_tibble()
  }



  return(res)

}

