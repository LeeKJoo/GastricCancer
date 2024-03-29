# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of RanitidineCancerRisk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


#' Create settings for adding subgroup markers as covariates
#'
#' @details
#' Creates a marker covariate for each of the subgroups of interest.
#'
#' @param windowStart   Start day of the window where covariates are captured, relative to the index
#'                      date (0 = index date).
#' @param windowEnd     End day of the window where covariates are captured, relative to the index date
#'                      (0 = index date).
#' @param analysisId    A unique identifier for this analysis.
#'
#' @return
#' A covariateSettings object.
#'
#' @export
createSubgroupCovariateSettings <- function(windowStart = -365, windowEnd = -1, analysisId = 998) {
  covariateSettings <- list(windowStart = windowStart,
                            windowEnd = windowEnd,
                            analysisId = analysisId)
  attr(covariateSettings, "fun") <- "aspirinDM::getDbSubgroupCovariateData"
  class(covariateSettings) <- "covariateSettings"
  return(covariateSettings)
}

#' Construct subgroup covariates
#'
#' @param connection          A connection to the server containing the schema as created using the
#'                            \code{connect} function in the \code{DatabaseConnector} package.
#' @param oracleTempSchema    A schema where temp tables can be created in Oracle.
#' @param cdmDatabaseSchema   The name of the database schema that contains the OMOP CDM instance.
#'                            Requires read permissions to this database. On SQL Server, this should
#'                            specifiy both the database and the schema, so for example
#'                            'cdm_instance.dbo'.
#' @param cohortTable         Name of the table holding the cohort for which we want to construct
#'                            covariates. If it is a temp table, the name should have a hash prefix,
#'                            e.g. '#temp_table'. If it is a non-temp table, it should include the
#'                            database schema, e.g. 'cdm_database.cohort'.
#' @param cohortId            For which cohort ID should covariates be constructed? If set to -1,
#'                            covariates will be constructed for all cohorts in the specified cohort
#'                            table.
#' @param cdmVersion          The version of the Common Data Model used. Currently only
#'                            \code{cdmVersion = "5"} is supported.
#' @param rowIdField          The name of the field in the cohort temp table that is to be used as the
#'                            row_id field in the output table. This can be especially usefull if there
#'                            is more than one period per person.
#' @param covariateSettings   An object created using the \code{createSubgroupCovariateSettings} function.
#' @param aggregated          Should aggregate statistics be computed instead of covariates per
#'                            cohort entry?
#'
#' @export
getDbSubgroupCovariateData <- function(connection,
                                       oracleTempSchema = NULL,
                                       cdmDatabaseSchema,
                                       vocabularyDatabaseSchema = cdmDatabaseSchema,
                                       cohortTable = "#cohort_person",
                                       cohortId = -1,
                                       cdmVersion = "5",
                                       rowIdField = "subject_id",
                                       covariateSettings,
                                       aggregated = FALSE) {
  if (aggregated)
    stop("Aggregation not supported")
  writeLines("Creating covariates HP eradication")
  sql <- SqlRender::loadRenderTranslateSql("CreateSubgroups.sql",
                                           packageName = "aspirinDM",
                                           dbms = connection@dbms,
                                           oracleTempSchema = oracleTempSchema,
                                           cdm_database_schema = cdmDatabaseSchema,
                                           vocabulary_database_schema = vocabularyDatabaseSchema,
                                           window_start = covariateSettings$windowStart,
                                           window_end = covariateSettings$windowEnd,
                                           analysis_id = covariateSettings$analysisId,
                                           row_id_field = rowIdField,
                                           cohort_temp_table = cohortTable,
                                           cohort_id = cohortId)
  DatabaseConnector::executeSql(connection, sql)
  
  sql <- SqlRender::loadRenderTranslateSql("GetSubgroups.sql",
                                           packageName = "aspirinDM",
                                           dbms = connection@dbms,
                                           oracleTempSchema = oracleTempSchema)
  covariates <- DatabaseConnector::querySql.ffdf(connection, sql)
  colnames(covariates) <- SqlRender::snakeCaseToCamelCase(colnames(covariates))
  
  sql <- SqlRender::loadRenderTranslateSql("DropSubgroupTempTables.sql",
                                           packageName = "aspirinDM",
                                           dbms = connection@dbms,
                                           oracleTempSchema = oracleTempSchema)
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  
  covariateRef <- data.frame(covariateId = c(1000) + covariateSettings$analysisId,
                             covariateName = c("HP eradication"),
                             analysisId = as.numeric(covariateSettings$analysisId),
                             conceptId = 0)
  covariateRef <- ff::as.ffdf(covariateRef)
  
  # Construct analysis reference:
  analysisRef <- data.frame(analysisId = as.numeric(covariateSettings$analysisId),
                            analysisName = "HP eradication",
                            domainId = "Cohort",
                            startDay = as.numeric(covariateSettings$windowStart),
                            endDay = as.numeric(covariateSettings$windowEnd),
                            isBinary = "Y",
                            missingMeansZero = "Y")
  analysisRef <- ff::as.ffdf(analysisRef)
  # Construct analysis reference:
  metaData <- list(sql = sql, call = match.call())
  result <- list(covariates = covariates,
                 covariateRef = covariateRef,
                 analysisRef = analysisRef,
                 metaData = metaData)
  class(result) <- "covariateData"
  return(result)
}