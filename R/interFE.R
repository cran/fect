# Interactive Fixed Effect Model
# Version 1.02
# LLC WY XYQ, 2019.2.2


## generic function
interFE <- function(formula=NULL,
                    data, # a data frame
                    Y, # outcome variable
                    X, # covariates
                    index, # id and time indicators
                    r = 0, # number of factors
                    force = "none", # additived fixed effects
                    se = TRUE, # standard error
                    nboots = 500, # number of bootstrap runs
                    seed = NULL,
                    tol = 1e-3,
                    binary = FALSE,
                    QR = FALSE,
                    normalize = FALSE) {
    UseMethod("interFE")
}

## formula method
interFE.formula <- function(formula=NULL, data, # a data frame
                            Y, # outcome variable
                            X, # covariates
                            index, # id and time indicators
                            r = 0, # number of factors
                            force = "none", # additived fixed effects
                            se = TRUE, # standard error
                            nboots = 500, # number of bootstrap runs
                            seed = NULL,
                            tol = 1e-3,
                            binary = FALSE,
                            QR = FALSE,
                            normalize = FALSE) {
    ## parsing
    varnames <- all.vars(formula)
    Yname <- varnames[1]
    Xname <- varnames[2:length(varnames)]

    ## check binary outcome
    if (binary == TRUE) {
        unique_y <- sort(unique(data[,Yname]))
        if (length(unique_y) != 2) {
            stop("Outcome should only contain 0 and 1.")
        } else {
            if (sum(unique_y == c(0,1)) != 2) {
                stop("Outcome should only contain 0 and 1.")
            }
        } 
    }
    
    ## run the model
    out <- interFE.default(formula=NULL, data = data, Y = Yname, X = Xname, 
                           index, # id and time indicators
                           r, # number of factors
                           force, # additived fixed effects
                           se, # standard error
                           nboots, # number of bootstrap runs
                           seed,
                           tol,
                           binary,
                           QR,
                           normalize)
    out$call <- match.call()
    out$formula <- formula
    return(out)
}


print.interFE <- function(x,
                         ...) {
    message("Call:\n")
    print(x$call, digits = 4)
    message("\nEstimated Coefficients:\n")
    print(x$est.table, digits = 4) 
}


###################################
# panel interactive fixed effects
###################################

interFE.default <- function(formula=NULL, data, # a data frame
                            Y, # outcome variable
                            X, # covariates
                            index, # id and time indicators
                            r = 0, # number of factors
                            force = "none", # additived fixed effects
                            se = TRUE, # standard error
                            nboots = 500, # number of bootstrap runs
                            seed = NULL,
                            tol = 1e-3,
                            binary = FALSE,
                            QR = FALSE,
                            normalize
                            ){ 
    
    ##-------------------------------#
    ## Parameters
    ##-------------------------------#  

    ## index
    if (length(index) != 2 | sum(index %in% colnames(data)) != 2) {
        stop("\"index\" option misspecified. Try, for example, index = c(\"unit.id\", \"time\").")
    }
    if (force == "none") { # no additive fixed effects imposed
        force <- 0
    } else if (force == "unit") { # unit fixed-effect
        force <- 1
    } else if (force == "time") { # time fixed-effect
        force <- 2
    } else if (force == "two-way") { # two-way fixed-effect 
        force <- 3
    }
    if (!force %in% c(0, 1, 2, 3)) {
        stop("\"force\" option misspecified; choose from c(\"none\", \"unit\", \"time\", \"two-way\").")
    } 
  
    ##-------------------------------#
    ## Parsing raw data
    ##-------------------------------#

    ## store variable names
    Yname <- Y
    Xname <- X
    id <- index[1]
    time <- index[2] 

    id.series <- unique(data[,id])
    ## sort data
    data <- data[order(data[,id], data[,time]), ]


    ## dimensions
    T <- length(unique(data[,time]))
    N <- length(unique(data[,id]))
    p<-length(Xname)

    ## normalize
    if (binary == TRUE) {
        normalize <- FALSE
    }
    norm.para <- NULL
    if (normalize==TRUE) {
        sd.Y <- sd(as.matrix(data[,Yname]))
        data[,c(Yname,Xname)] <- data[,c(Yname,Xname)]/sd.Y
        ## if (length(Xname)>0) {
        ##     sd.X <- apply(as.matrix(data[,Xname]),2,sd)
        ##     data[,Xname] <- as.matrix(data[,Xname])/sd.X
        ##     norm.para <- c(sd.Y,sd.X)
        ## } else {
            norm.para <- sd.Y
        ## }   
    }

    if (p > 0) {
        for (i in 1:p) {
            if (sum(is.na(data[, Xname[i]])) > 0) {
                stop(paste("Missing values in variable \"", Xname[i],"\".", sep = ""))
            }

            if (sum(tapply(data[, Xname[i]], data[, id], var), na.rm = TRUE) == 0) {
              stop(paste("Variable \"",Xname[i], "\" is unit-invariant. Try to remove it.", sep = ""))
            }
            if (sum(tapply(data[, Xname[i]], data[, time], var), na.rm = TRUE) == 0) {
              stop(paste("Variable \"",Xname[i], "\" is time-invariant. Try to remove it.", sep = ""))
            }
        }
    }

    ## check balanced panel
    if (dim(data)[1] < T*N) {
        data[,time] <- as.numeric(as.factor(data[,time]))
        ## ob <- "time_ob_ls"
        
        ## while (ob %in% colnames(data)) {
        ##     ob <- paste(ob, ob, sep = "_")
        ## }

        ## data[, ob] <- data[, time]
        ## for (i in 1:N) {
        ##     data[data[,id] == id.series[i], ob] <- data[data[,id] == id.series[i],time] + (i - 1) * TT  
        ## }

        ob.indicator <- data[,time]
        id.indicator <- table(data[, id])
        sub.start <- 1
        for (i in 1:(N - 1)) { 
            sub.start <- sub.start + id.indicator[i] 
            sub.end <- sub.start + id.indicator[i+1] - 1 
            ob.indicator[sub.start:sub.end] <- ob.indicator[sub.start:sub.end] + i * T
        }

        variable <- c(Yname, Xname)

        data_I <- matrix(0, N * T, 1)
        data_I[ob.indicator, 1] <- 1
        data_ub <- as.matrix(data[, variable])
        data <- data_ub_adj(data_I, data_ub)
        colnames(data) <- variable
    }

    I <- matrix(1,T,N)
    Y.ind <- matrix(data[,Yname],T,N)
    I[is.nan(Y.ind)] <- 0

    if (0%in%I) {
        data[is.nan(data)] <- 0
    }
    
    ## parse data
    Y <- matrix(data[,Yname],T,N)
    
    ## time-varying covariates
    X <- array(0, dim = c(T, N, p))
    #xp <- rep(0, p) ## label invariant x
    #x.pos <- 0

    if (p > 0) {
        #x.pos <- 1:p
        for (i in 1:p) {
            X[,,i] <- matrix(data[, Xname[i]], T, N)
            #if (force %in% c(1,3)) {
            #    if (!0%in%I) {
            #        tot.var.unit <- sum(apply(X[, , i], 2, var))
            #    } else {
            #        Xi <- X[,,i]
            #        Xi[which(I == 0)] <- NA
            #        tot.var.unit <- sum(apply(Xi, 2, var, na.rm = TRUE))
            #    }
            #    if(!is.na(tot.var.unit)) {
            #        if (tot.var.unit == 0) {
                        ## time invariant covar can be removed
            #            xp[i] <- 1
            #            message(paste("Variable \"", Xname[i],"\" is time-invariant.\n", sep = ""))   
            #        }
            #    }
            #}
            #if (force %in% c(2, 3)) {
            #    if (!0%in%I) {
            #        tot.var.time <- sum(apply(X[, , i], 1, var))
            #    } else {
            #        Xi <- X[,,i]
            #        Xi[which(I == 0)] <- NA
            #        tot.var.time <- sum(apply(Xi, 1, var, na.rm = TRUE))
            #    } 
            #    if (!is.na(tot.var.time)) {
            #        if (tot.var.time == 0) {
                        ## can be removed in inter_fe
            #            xp[i] <- 1
            #            message(paste("Variable \"", Xname[i],"\" has no cross-sectional variation.\n", sep = ""))
            #        }
            #    }
            #} 
        } 
    }

    #if (sum(xp) > 0) {
    #    if (sum(xp) == p) {
    #        X <- array(0, dim = c(T, N, 0))
    #        p <- 0
    #    } else {
    #        x.pos <- which(xp == 0)
    #        Xsub <- array(0, dim = c(T, N, length(x.pos)))
    #        for (i in 1:length(x.pos)) {
    #            Xsub[,,i] <- X[,,x.pos[i]] 
    #        }
    #        X <- Xsub
    #        p <- length(x.pos)
    #    }
    #} 
  
    ##-------------------------------#
    ## Estimation
    ##-------------------------------#
    initialOut <- Y0 <- NULL
    FE0 <- xi0 <- factor0 <- NULL
    beta0 <- matrix(0,1,1)
    if (p > 0) {
        beta0 <- as.matrix(rep(0, p))
    }

    if (0 %in% I || binary == TRUE) {
        data.ini <- matrix(NA, (T*N), (2 + 1 + p))
        data.ini[, 2] <- rep(1:N, each = T)         ## unit fe
        data.ini[, 3] <- rep(1:T, N)                ## time fe
        data.ini[, 1] <- c(Y)                       ## outcome
        if (p > 0) {                                ## covar
            for (i in 1:p) {
                data.ini[, (3 + i)] <- c(X[, , i])
            }
        }

        if (binary == FALSE) {
            initialOut <- initialFit(data.ini, force, which(c(I) == 1))
            Y0 <- initialOut$Y0
            if (p > 0) {
                beta0 <- initialOut$beta0
            }
        } else {
            initialOut <- BiInitialFit(data = data.ini, QR = QR, r = r, force = force, oci = which(c(I) == 1))
            Y0 <- initialOut$Y0
            FE0 <- initialOut$FE0
            if (QR == 1) {
                xi0 <- initialOut$xi0
                factor0 <- initialOut$factor0
            }
        }
    } 

    ## estimates
    if (binary == FALSE) {
        if (!0%in%I) {
            out<-inter_fe(Y = Y, X = X, r = r, beta0 = beta0, force = force)
        } else {
            out<-inter_fe_ub(Y = Y, Y0 = Y0, X = X, I = I, beta0 = beta0, r = r, force = force)
        }
    } else {
        if (QR == FALSE) {
            if (!0%in%I) {
                out <- inter_fe_d(Y, Y0, FE0, X, r = r, force, tol = tol)
            } else {
                out <- inter_fe_d_ub(Y, Y0, FE0, X, I, r = r, force, tol = tol)
            }
        } else {
            if (!0%in%I) {
                out <- inter_fe_d_qr(Y, Y0, FE0, factor0, xi0, X, r = r, force, tol = tol)
            } else {
                out <- inter_fe_d_qr_ub(Y, Y0, FE0, factor0, xi0, X, I, r = r, force, tol = tol)
            }
        }
    }
    
    
    if (is.null(norm.para)) {
        beta<-as.matrix(out$beta)
        mu <- out$mu
        if (!0 %in% I) {
            beta0 <- beta
            beta0[is.nan(beta0)] <- 0
        }
    } else {
        mu <- out$mu*norm.para[1]
        if (p>0) {
            beta<-as.matrix(out$beta)
            if (!0 %in% I) {
                beta0 <- beta
                beta0[is.nan(beta0)] <- 0
            }
            ## beta<-as.matrix(out$beta)*norm.para[1]/norm.para[2:length(norm.para)]
        }
    }
    

    ##-------------------------------#
    ## Standard Errors
    ##-------------------------------#

    ## function to get two-sided p-values
    get.pvalue <- function(vec) {
        if (NaN%in%vec|NA%in%vec) {
            nan.pos <- is.nan(vec)
            na.pos <- is.na(vec)
            pos <- c(which(nan.pos),which(na.pos))
            vec.a <- vec[-pos]
            a <- sum(vec.a >= 0)/(length(vec)-sum(nan.pos|na.pos)) * 2
            b <- sum(vec.a <= 0)/(length(vec)-sum(nan.pos|na.pos)) * 2  
        } else {
            a <- sum(vec >= 0)/length(vec) * 2
            b <- sum(vec <= 0)/length(vec) * 2  
        }
        return(min(as.numeric(min(a, b)),1))
    }

    if (se == TRUE) {
        if (is.null(seed) == FALSE) {
            set.seed(seed)
        }
        ## to store results
        est.boot <- matrix(NA,nboots,(p+1))
        message("Bootstraping...\n")
        for (i in 1:nboots) {
            smp <- sample(1:N, N , replace=TRUE)
            Y.boot <- Y[,smp]
            X.boot<-X[,smp,,drop=FALSE]
            I.boot <- I[,smp]

            if (binary == FALSE) {
                if (!0%in%I) {
                    inter.out <- try(inter_fe(Y=Y.boot, X=X.boot, r=r,
                                          force=force, beta0 = beta0), silent = TRUE)
                } else {
                    Y0.boot <- Y0[,smp]
                    inter.out <- try(inter_fe_ub(Y=Y.boot, Y0=Y0.boot, X=X.boot, I=I.boot, 
                                             beta0 = beta0, r=r, force=force), silent = TRUE)
                }
            } else {

                data.ini.boot <- matrix(NA, (T*N), (2 + 1 + p))
                data.ini.boot[, 2] <- rep(1:N, each = T)         ## unit fe
                data.ini.boot[, 3] <- rep(1:T, N)                ## time fe
                data.ini.boot[, 1] <- c(Y.boot)                       ## outcome
                if (p > 0) {                                ## covar
                    for (j in 1:p) {
                        data.ini.boot[, (3 + j)] <- c(X.boot[, , j])
                    }
                }
                initialOut.boot <- BiInitialFit(data = data.ini.boot, QR = QR, r = r, force = force, oci = which(c(I.boot) == 1))
                Y0.boot <- initialOut.boot$Y0
                FE0.boot <- initialOut.boot$FE0
                if (QR == 1) {
                    xi0.boot <- initialOut.boot$xi0
                    factor0.boot <- initialOut.boot$factor0
                }

                if (QR == FALSE) {
                    if (!0%in%I) {
                        inter.out <- try(inter_fe_d(Y.boot, Y0.boot, FE0.boot, X.boot, r = r, force, tol = tol), silent = TRUE)
                    } else {
                        inter.out <- try(inter_fe_d_ub(Y.boot, Y0.boot, FE0.boot, X.boot, I.boot, r = r, force, tol = tol), silent = TRUE)
                    }
                } else {
                    if (!0%in%I) {
                        inter.out <- try(inter_fe_d_qr(Y.boot, Y0.boot, FE0.boot, factor0.boot, xi0.boot, X.boot, r = r, force, tol = tol), silent = TRUE)
                    } else {
                        inter.out <- try(inter_fe_d_qr_ub(Y.boot, Y0.boot, FE0.boot, factor0.boot, xi0.boot, X.boot, I.boot, r = r, force, tol = tol), silent = TRUE)
                    }
                }

            }

            if ('try-error' %in% class(inter.out)) {
                inter.out <- list(beta = NA, mu = NA)
            } else {
                if (is.null(norm.para)) {
                    est.boot[i,]<- c(c(inter.out$beta), inter.out$mu)
                } else {
                    if(p>0){
                        est.boot[i,]<- 
                            c(c(inter.out$beta), 
                                inter.out$mu*norm.para[1])
                    } else {
                        est.boot[i,]<- c(c(inter.out$beta), inter.out$mu*norm.para[1])    
                    }
                }
            }
            
            if (i%%100==0) {message(".")}
        }
        message("\r")
        ## T*2: lower,upper
        CI<-t(apply(est.boot,2,function(vec)
            quantile(vec,c(0.025,0.975),na.rm=TRUE)))
        SE<-apply(est.boot,2,sd, na.rm = TRUE)
        pvalue <- apply(est.boot, 2, get.pvalue)
         
        ## estimate table
        est.table<-cbind(c(beta,mu), SE, CI, pvalue)
        colnames(est.table) <- c("Coef","S.E.","CI.lower","CI.upper", "p.value")
    } else {
        est.table <- as.matrix(c(beta,mu))
    }
    rownames(est.table) <- c(Xname,"_const")
    
    ##-------------------------------#
    ## Storage
    ##-------------------------------# 
    if (!is.null(norm.para)) {
        out$mu <- out$mu*norm.para[1]
        if (p>0) {
            out$beta <- out$beta
        }
        if (r>0) {
            out$lambda <- out$lambda*norm.para[1]
            out$VNT <- out$VNT*norm.para[1]
        }
        if (force%in%c(1,3)) {
            out$alpha <- out$alpha*norm.para[1]
        }
        if (force%in%c(2,3)) {
            out$xi <- out$xi*norm.para[1]
        }
        out$IC <- out$IC - log(out$sigma2) + log(out$sigma2*(norm.para[1]^2))
        out$PC <- out$PC*(norm.para[1]^2)
        out$sigma2 <- out$sigma2*(norm.para[1]^2)
        out$residuals <- out$residuals*norm.para[1]  
        out$fit <- out$fit*norm.para[1]   
    }
   
    out<-c(out, list(dat.Y = Y,
                     dat.X = X,
                     Y = Yname,
                     X = Xname,
                     index = c(id,time)))
    if (se == TRUE) {
        out <- c(out,list(est.table = est.table,
                          est.boot = est.boot # bootstrapped coef.
                          ))
    } else {
        out <- c(out, list(est.table = est.table))
    }
    class(out) <- "interFE"
    return(out)

}




