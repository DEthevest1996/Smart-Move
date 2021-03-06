
library(rvest)
library(tidyverse)
library(jsonlite)
library(datasets)
library(blsAPI)
library(RSelenium)
library(XML)
library(mongolite)
library(forecast)
library(TSA)


# Health Care ####

Race_and_Income <- c("White","Black","Hispanic","NHPI",
  "Asian","AI_AN","Non-Hispanic_White","Low_Income","High_Income")

Measures_identifier <- data.frame(Measure = c(),
                                  Race_Ethnicity = c(),
                                  Estimate =c(),
                                  State = c())

for(l in 1:length(state.name)){
  url <- paste0( "https://nhqrnet.ahrq.gov/inhqrdr/",gsub(" ","%20",state.name[l]),
    "/benchmark/table/Priority_Populations/")
  for (k in 1:length(Race_and_Income)) {
    Identifying_vars <- read_html(paste0(url, Race_and_Income[k])) %>% html_table() 
    if(length(Identifying_vars) > 0){
      for(i in 1:length(Identifying_vars)){  Measures_identifier_2 <- 
        data.frame(Measure = c(Identifying_vars[[i]][1]), 
                   Race_Ethnicity = c(Race_and_Income[i]),
                   Estimate = c(Identifying_vars[[i]][3]),
                   State = c(state.name[l]),
                   Benchmark = c(Identifying_vars[[i]][5]))
      Measures_identifier <- rbind(Measures_identifier,Measures_identifier_2)
      Sys.sleep(2)
      }
    }
  }
}
Measures_identifier <- separate(Measures_identifier,
                               Distance.to.Benchmark,
                               into = c("Ratio","1","2"),sep = " ")
Measures_identifier$Ratio <- gsub("Achieved:",NA,lala$Ratio)
Measures_identifier <- unite(lala,"Ratio",c(5,6),na.rm = TRUE)

HealthCare <- mongo(collection = "HealthCare",'admin')
HealthCare$insert(Measures_identifier)


# Mortality & Safety ####

Compressed_Mortality <-  read_delim("Mortality/Compressed Mortality, 1999-2016.txt", 
                                    "\t", escape_double = FALSE, trim_ws = TRUE)
for (i in 1:14) {
  Compressed_Mortality_2 <- read_delim(paste0(
                                    "Mortality/Compressed Mortality, 1999-2016(",i,").txt"),"\t")
  if(ncol(Compressed_Mortality_2) == 12){Compressed_Mortality_2$`% of Total Deaths` <- NA}
  Compressed_Mortality <- rbind(Compressed_Mortality,Compressed_Mortality_2)}

Compressed_Mortality <- select(Compressed_Mortality,c(2,4,6,8,10,11))
Compressed_Mortality <- rename(Compressed_Mortality,"Cause" = "Cause of death")



# STATE Level
crime <- fromJSON(
  "https://api.usa.gov/crime/fbi/sapi/api/summarized/estimates/states/FL/2010/2018?API_KEY=iiHnOKfno2Mgkt5AynpvPpUQTEyxE77jo1RU8PIv"
)[[1]]
for(i in 2:length(state.abb)){
  crime <- rbind(crime,fromJSON(paste0(
    "https://api.usa.gov/crime/fbi/sapi/api/summarized/estimates/states/",state.abb[i],
    "/2010/2018?API_KEY=iiHnOKfno2Mgkt5AynpvPpUQTEyxE77jo1RU8PIv"
  ))[[1]])  
}


# STATE Level
police <- fromJSON(
  "https://api.usa.gov/crime/fbi/sapi/api/police-employment/states/AL/2010/2018?API_KEY=iiHnOKfno2Mgkt5AynpvPpUQTEyxE77jo1RU8PIv"
)[[1]]

for(i in 2:length(state.abb)){
  police <- rbind(police,fromJSON(paste0(
    "https://api.usa.gov/crime/fbi/sapi/api/police-employment/states/",state.abb[i],
    "/2010/2018?API_KEY=iiHnOKfno2Mgkt5AynpvPpUQTEyxE77jo1RU8PIv"
  ))[[1]])  
}
Safety <- mongo(collection = "Public Safety", db = "admin")
Safety$insert(police)
mongo(collection = "Crime", db = "admin")$insert(crime)

Compressed_Mortality %>%
  write.csv("Compressed_Mortality.csv")

# Income ####

blsIncome <- read_html(paste0("https://www.bls.gov/oes/current/oes_",
                 str_to_lower(state.abb[1]),".htm")) %>%
  html_table(fill = TRUE)
blsIncome <- as.data.frame(blsIncome[2])
blsIncome <- rename(blsIncome,"OcupationTitle" = names(blsIncome)[2])
blsIncome$State <- state.name[1]

for(i in 2:length(state.abb)){ 
  blsIncome_2 <- read_html(paste0("https://www.bls.gov/oes/current/oes_",
                                str_to_lower(state.abb[i]),".htm")) %>%
    html_table(fill = TRUE) 
  blsIncome_2 <- blsIncome_2[[2]]
  blsIncome_2$State <- state.name[i]
  colnames(blsIncome_2) <- names(blsIncome)
  blsIncome <- blsIncome %>% rbind(blsIncome_2)

}

mongo(collection = "Income", db = "admin")$insert(blsIncome)

# Traffic levels ####
library(RSelenium)
library(XML)
remDr <- remoteDriver(port = 4567)

remDr$open()

remDr$navigate("https://www.tomtom.com/en_gb/traffic-index/ranking/?country=US")

doc <- htmlParse(remDr$getPageSource()[[1]])
traffic <- as.data.frame(readHTMLTable(doc)$'NULL')

s <- as.numeric(unlist(strsplit(
  as.character(traffic$`Congestion Level`),"%",fixed= TRUE)))
traffic$`Congestion Level` <- s[seq(1,length(s),2)] 

worldRanking <- traffic$`World Rank`[1]
NationalRanking <- traffic$`Rank by filter`[1]

trafficMongo <- mongo(collection = "traffic" ,"admin")$insert(traffic)


# Housing ####

rent <- read.csv("Housing/County_Zri_AllHomesPlusMultifamily.csv") %>%
  select(-c(4,5,6,7))
rent$RegionName <- gsub("County","",rent$RegionName)

mongo("Rent", "admin")$insert(rent)

# Weather #### 

# It uses data tables available at U.S Climate Data. The inputs are State >> City. 

# input desired state

# The process starts with choosing a State from the home site.

# navigates to the web and extracts the links for the states data
Main <- read_html('https://www.usclimatedata.com') %>% html_nodes("a")  %>% html_attr("href")

dfWeather <- data.frame()
for(i in 38:length(state.name)){
  # navigates to the desired state by searching for the right link, to do that
  #   the grep function searches for the state name among all the links listed on Main
  #   Finally, the href returns a list of city data links
  StateCities <- read_html(paste0("https://www.usclimatedata.com",
    grep(state.name[i],Main,ignore.case = TRUE,value = TRUE))[1]) %>% html_nodes("a") %>% html_attr("href")
  
  NameCities <- c() # empty variable
  # separate the names of the cities from undesired characters.
  # the intention is to use the names as input
  for(p in 10:(length(strsplit(StateCities,"/"))-3)){ 
    NameCities[p] <- c(strsplit(StateCities,"/")[[p]][3])}
  NameCities <- sort(NameCities[!is.na(NameCities)]) 
  
  for(k in 1:length(NameCities)){
    # navigates to the desired city by searching for the right link, to do that
    #   the grep function searches for the city name among all the links listed on Main
    #   Finally, the html_table returns the weather data tables 
    CityTables <- read_html(paste0("https://www.usclimatedata.com",
      grep(NameCities[k],StateCities,ignore.case = TRUE,value = TRUE))[1]) %>% 
      html_table()
    
    # combining monthly data to make a dataframe with the whole year
    if(length(CityTables) == 8){
      CityWeather <- cbind(CityTables[[1]],CityTables[[2]]) %>% select(c(-8)) %>%
        rename("Index"="Var.1")  # corrects the names of the months
      for(o in 2:ncol(CityWeather)){colnames(CityWeather)[o] <- unlist(strsplit(names(CityWeather)[o], 
                                          "(?<=[a-z])(?=[A-Z])",  perl = TRUE))[1]}
      dat <- as.data.frame(t(CityWeather))
      names(dat) <- as.matrix(dat[1, ])
      dat <- dat[-1, ]
      dat[] <- lapply(dat, function(x) type.convert(as.character(x)))
      
      dat$State <- state.name[i]
      dat$City <- NameCities[k]
      if(ncol(dat) > 5){ dat <- select(dat,c(1,2,3,5,6))} else if(ncol(dat) < 5){} 
      else {  dfWeather<- rbind(dfWeather,dat)}
    }
  }
  Sys.sleep(5)
}

mongo(collection = "Weather", "admin")$insert(dfWeather)


