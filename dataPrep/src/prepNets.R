## calculate the difference in the number of vists a plant receives
getDiffVisits <- function(site, dats, metrics, sp.type){
    dats <- dats[dats$Site == site,]
    early <- dats[dats$assem == "early", c("types", "visits")]
    late <- dats[dats$assem == "late", c("types", "visits")]

    ## add zeros to plant species that were not visited in early/late assem
    not.in.late <- early[, "types"][!early[, "types"] %in%
                                    late[, "types"]]
    late <- rbind(late, data.frame(types=not.in.late,
                                   visits=rep(0,
                                              length(not.in.late))))
    not.in.early <- late[, "types"][!late[, "types"] %in%
                                    early[, "types"]]
    early <- rbind(early, data.frame(types=not.in.early,
                                     visits=rep(0,
                                                length(not.in.early))))

    late <- late[match(early[, "types"], late[, "types"]),]
    diffs <- late[, metrics] - early[, metrics]
    early <- cbind(early, late$visits, diffs)
    colnames(early) <- c(sp.type, "earlyVisits",
                         "lateVisits", "diffVisits")
    return(early)
}


## difference in the number of visits
getVisitChange <- function(cut.off1, cut.off2, metric, type, type2){
    if(type == "GenusSpecies"){
        sp <- "plant"
    } else{
        sp <- "pollinator"
    }
    gen.pols <- specializations$GenusSpecies[specializations$speciesType ==
                                             sp &
                                             specializations[, metric]
                                             >= cut.off1 &
                                                specializations[, metric]
                                             <= cut.off2]
    gen.spec <- spec[spec[, type2] %in% gen.pols,]

    agg.gen.spec <- aggregate(list(visits=gen.spec[, type]),
                              list(assem=gen.spec$assem,
                                   Site=gen.spec$Site,
                                   types=gen.spec[, type]),
                              length)


    visit.diffs <- lapply(unique(agg.gen.spec$Site), getDiffVisits,
                          dats=agg.gen.spec, metrics="visits",
                          sp.type= type)

    sites <- rep(unique(agg.gen.spec$Site), times=sapply(visit.diffs, nrow))

    visit.diffs <- do.call(rbind, visit.diffs)

    visit.diffs <- cbind(visit.diffs,
                         specializations[match(
                             visit.diffs[, type],
                             specializations$GenusSpecies[specializations$assem
                                                          == "early"]),
                             c("normalised.degree",
                               "d",
                               "proportional.generality")])
    visit.diffs$Site <- sites
    return(visit.diffs)
}




## the purpose of this function is to break up data with many
## sites/years and prepre it for network analysis.

dropNet <- function(z){
    z[!sapply(z, FUN=function(q){
        any(dim(q) < 5)
    })]
}

breakNet <- function(spec.dat, site, year){
    ## puts data together in a list and removes empty matrices
    agg.spec <- aggregate(list(abund=spec.dat$GenusSpecies),
                          list(GenusSpecies=spec.dat$GenusSpecies,
                               SampleRound=spec.dat$SampleRound,
                               Site=spec.dat[,site],
                               Year=spec.dat[,year],
                               PlantGenusSpecies=spec.dat$PlantGenusSpecies),
                          length)
    agg.spec <- aggregate(list(abund=agg.spec$abund),
                          list(GenusSpecies=agg.spec$GenusSpecies,
                               Site=agg.spec$Site,
                               Year=agg.spec$Year,
                               PlantGenusSpecies=agg.spec$PlantGenusSpecies),
                          mean)
    sites <- split(agg.spec, agg.spec[,site])
    networks <- lapply(sites, function(x){
        split(x, f=x[,year])
    })
    ## formats data matrices appropriate for network analysis
    comms <- lapply(unlist(networks, recursive=FALSE), function(y){
        samp2site.spp(site=y[,"PlantGenusSpecies"],
                      spp=y[,"GenusSpecies"],
                      abund=y[,"abund"])
    })
    comms <- dropNet(comms)
    if(year == "assem"){
        names(comms) <- sub("\\.", "_", names(comms),
                            perl=TRUE)
    }
    return(comms)
}



breakNetSpTemp <- function(spec.dat, site, year){
    ## puts data together in a list and removes empty matrices
    agg.spec <- aggregate(list(abund=spec.dat$GenusSpecies),
                          list(GenusSpecies=spec.dat$GenusSpecies,
                               SampleRound=spec.dat$SampleRound,
                               Site=spec.dat[,site],
                               Year=spec.dat[,year]),
                          length)
    ## take the mean acoss sampling rounds to account for unequal sampling
    agg.spec <- aggregate(list(abund=agg.spec$abund),
                          list(GenusSpecies=agg.spec$GenusSpecies,
                               Site=agg.spec$Site,
                               Year=agg.spec$Year),
                          mean)
    networks <- split(agg.spec, agg.spec[, "Site"])
    ## formats data matrices appropriate for network analysis
    comms <- lapply(networks, function(y){
        samp2site.spp(site=y[, "Year"],
                      spp=y[,"GenusSpecies"],
                      abund=y[,"abund"])
    })
    comms <- dropNet(comms)
    return(comms)
}

getSpecies <- function(networks, FUN){
    species.site <- lapply(networks, FUN)
    site.plant <- rep(names(species.site), lapply(species.site, length))
    species <- data.frame(species=do.call(c, species.site),
                          siteStatus=site.plant,
                          site= sapply(strsplit(site.plant, "_"), function(x)
                              x[1]),
                          status= sapply(strsplit(site.plant, "_"), function(x)
                              x[2]))
    return(species)
}


## saves each element of a list with corresponding name
saveDats <- function(x, y, f.path){
    mapply(function(a, b)
        write.csv(a, file=file.path(f.path,
                                    sprintf("%s.csv", b))),
        a=x, b=y,
        SIMPLIFY=FALSE)
}


## calculates the degree of species in a network
getDegree <- function(x, MARGIN){
    apply(x, MARGIN, function(y){
        length(y[y != 0])/length(y)
    })
}

## calculate various stats
calcStats <- function(x){
    means=mean(x)
    medians=median(x)
    mins <- min(x)
    maxs <- max(x)
    sds <- sd(x)
    return(c(mean=means,
             median=medians,
             min=mins,
             max=maxs,
             sd=sds))
}


##  species differences between early and late stages
getColExt <- function(dats){
    out <- lapply(unique(dats$site), function(x){
        this.site <- dats[dats$site == x,]
        early <- this.site$species[this.site$status == "early"]
        late <- this.site$species[this.site$status == "late"]
        colonists <- as.character(late[!late %in% early])
        ext <- as.character(early[!early %in% late])
        species <- c(colonists, ext)
        return(data.frame(species=species,
                          class=c(rep("colonist", length(colonists)),
                                  rep("extinction", length(ext))),
                          site=rep(x, length(species))))
    })
    out <- do.call(rbind, out)
    return(out)
}


## number of species that interact
getCon <- function(x, INDEX){
    apply(x, INDEX, function(y) sum(y > 0))
}


## extreact specialization scores from specieslevel function and
## return data frame
getSpec <- function(species.lev, names.net, seps="_"){
    n.pp <- sapply(species.lev, nrow)
    pp <- c(unlist(sapply(species.lev, rownames)))
    names(pp) <- NULL
    all.pp <- do.call(rbind, species.lev)
    rownames(all.pp) <- NULL
    try(all.pp$GenusSpecies <- pp)
    all.pp$speciesType <- c(rep("pollinator", n.pp[1]),
                            rep("plant", n.pp[2]))
    all.pp$Site <- strsplit(names.net, seps)[[1]][1]
    all.pp$assem <- strsplit(names.net, seps)[[1]][2]
    return(all.pp)
}

