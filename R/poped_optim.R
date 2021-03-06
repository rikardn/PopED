#' Optimization main module for PopED
#' 
#' Optimize the objective function. The function works for both discrete and 
#' continuous optimization variables. If more than one optimization method is 
#' specified then the methods are run in series.  If \code{loop_methods=TRUE} 
#' then the series of optimization methods will be run for \code{iter_max} 
#' iterations, or until the efficiency of the design after the current series 
#' (compared to the start of the series) is less than \code{stop_crit_eff}.
#' 
#' This function takes information from the PopED database supplied as an 
#' argument. The PopED database supplies information about the the model, 
#' parameters, design and methods to use. Some of the arguments coming from the 
#' PopED database can be overwritten; if they are supplied then they are used 
#' instead of the arguments from the PopED database.
#' 
#' @inheritParams RS_opt
#' @inheritParams Doptim
#' @inheritParams create.poped.database
#' @inheritParams Dtrace
#' @inheritParams calc_ofv_and_fim
#' @inheritParams optim_LS
#' @param ... arguments passed to other functions.
#' @param control Contains control arguments for each method specified.
#' @param method A vector of optimization methods to use in a sequential 
#'   fashion.  Options are \code{c("ARS","BFGS","LS","GA")}. \code{c("ARS")} is 
#'   for Adaptive Random Search \code{\link{optim_ARS}}.  \code{c("LS")} is for 
#'   Line Search \code{\link{optim_LS}}. \code{c("BFGS")} is for Method 
#'   "L-BFGS-B" from \code{\link[stats]{optim}}. \code{c("GA")} is for the 
#'   genetic algorithm from \code{\link[GA]{ga}}.
#' @param out_file Save output from the optimization to a file.
#' @param loop_methods Should the optimization methods be looped for
#'   \code{iter_max} iterations, or until the efficiency of the design after the
#'   current series (compared to the start of the series) is less than, or equal to,
#'   \code{stop_crit_eff}?
#' @param stop_crit_eff If \code{loop_methods==TRUE}, the looping will stop if the
#'   efficiency of the design after the current series (compared to the start of
#'   the series) is less than, or equal to, \code{stop_crit_eff} (if \code{maximize==FALSE} then 1/stop_crit_eff is the cut
#'   off and the efficiency must be greater than or equal to this value to stop the looping).
#' @param stop_crit_diff If \code{loop_methods==TRUE}, the looping will stop if the
#'   difference in criterion value of the design after the current series (compared to the start of
#'   the series) is less than, or equal to, \code{stop_crit_diff} (if \code{maximize==FALSE} then -stop_crit_diff is the cut
#'   off and the difference in criterion value must be greater than or equal to this value to stop the looping).
#' @param stop_crit_rel If \code{loop_methods==TRUE}, the looping will stop if the
#'   relative difference in criterion value of the design after the current series (compared to the start of
#'   the series) is less than, or equal to, \code{stop_crit_rel} (if \code{maximize==FALSE} then -stop_crit_rel is the cut
#'   off and the relative difference in criterion value must be greater than or equal to this value to stop the looping).
#' @param maximize Should the objective function be maximized or minimized?
#'   
#'   
#'   
#' @references \enumerate{ \item M. Foracchia, A.C. Hooker, P. Vicini and A. 
#'   Ruggeri, "PopED, a software fir optimal experimental design in population 
#'   kinetics", Computer Methods and Programs in Biomedicine, 74, 2004. \item J.
#'   Nyberg, S. Ueckert, E.A. Stroemberg, S. Hennig, M.O. Karlsson and A.C. 
#'   Hooker, "PopED: An extended, parallelized, nonlinear mixed effects models 
#'   optimal design tool", Computer Methods and Programs in Biomedicine, 108, 
#'   2012. }
#'   
#' @family Optimize
#'   
#' @example tests/testthat/examples_fcn_doc/warfarin_optimize.R
#' @example tests/testthat/examples_fcn_doc/examples_poped_optim.R
#' @export

poped_optim <- function(poped.db,
                        opt_xt=poped.db$settings$optsw[2],
                        opt_a=poped.db$settings$optsw[4],
                        opt_x=poped.db$settings$optsw[3],
                        opt_samps=poped.db$settings$optsw[1],
                        opt_inds=poped.db$settings$optsw[5],
                        method=c("ARS","BFGS","LS"),
                        control=list(),
                        trace = TRUE,
                        fim.calc.type=poped.db$settings$iFIMCalculationType,
                        ofv_calc_type=poped.db$settings$ofv_calc_type,
                        approx_type=poped.db$settings$iApproximationMethod,
                        d_switch=poped.db$settings$d_switch,
                        ED_samp_size = poped.db$settings$ED_samp_size,
                        bLHS=poped.db$settings$bLHS,
                        use_laplace=poped.db$settings$iEDCalculationType,
                        out_file="",
                        parallel=F,
                        parallel_type=NULL,
                        num_cores = NULL,
                        loop_methods=ifelse(length(method)>1,TRUE,FALSE),
                        iter_max = 10,
                        stop_crit_eff = 1.001,
                        stop_crit_diff = NULL,
                        stop_crit_rel = NULL,
                        ofv_fun = poped.db$settings$ofv_fun,
                        maximize=T,
                        ...){
  
  #------------ update poped.db with options supplied in function
  called_args <- match.call()
  default_args <- formals()
  for(i in names(called_args)[-1]){
    if(length(grep("^poped\\.db\\$",capture.output(default_args[[i]])))==1) {
      #eval(parse(text=paste(capture.output(default_args[[i]]),"<-",called_args[[i]])))
      eval(parse(text=paste(capture.output(default_args[[i]]),"<-",i)))
    }
  }
  
  #----------- checks
  if((sum(poped.db$settings$optsw)==0)){
    stop('No optimization parameter is set.')
  }
  
  if(is.null(ofv_fun) || is.function(ofv_fun)){
    ofv_fun_user <- ofv_fun 
  } else {
    # source explicit file
    # here I assume that function in file has same name as filename minus .txt and pathnames
    if(file.exists(as.character(ofv_fun))){
      source(as.character(ofv_fun))
      ofv_fun_user <- eval(parse(text=fileparts(ofv_fun)[["filename"]]))
    } else {
      stop("ofv_fun is not a function or NULL, and no file with that name was found")
    }
    
  }
  if(!is.null(ofv_fun)){
    poped.db$settings$ofv_calc_type = 0
  }
  
  
  
  #---------- functions
  dots <- function(...) {
    eval(substitute(alist(...)))
  }
  
  #------------- initialization
  fmf = 0 #The best FIM so far
  dmf = 0 #The best ofv of FIM  so far
  #output <-calc_ofv_and_fim(poped.db,...)
  output <-calc_ofv_and_fim(poped.db,d_switch=d_switch,
                            ED_samp_size=ED_samp_size,
                            bLHS=bLHS,
                            use_laplace=use_laplace,
                            ofv_calc_type=ofv_calc_type,
                            fim.calc.type=fim.calc.type,
                            ofv_fun = ofv_fun_user,
                            ...)
  
  fmf <- output$fim
  dmf <- output$ofv
  fmf_init <- fmf
  dmf_init <- dmf
  
  if(is.nan(dmf_init)) stop("Objective function of initial design is NaN")
  
  #--------------------- write out info to a file
  fn=blockheader(poped.db,name="optim",e_flag=!d_switch,
                 fmf=fmf_init,dmf=dmf_init,
                 out_file=out_file,
                 trflag=trace,
                 ...)
  
  # Collect the parameters to optimize
  par <- c()
  upper <- c()
  lower <- c()
  par_grouping <- c()
  par_type <- c()
  par_dim <- list()
  allowed_values <- NULL
  build_allowed_values <- FALSE
  if(!is.null(poped.db$design_space$xt_space) ||
     !is.null(poped.db$design_space$a_space)) build_allowed_values <- TRUE
  if(opt_samps) stop('Sample number optimization is not yet implemented in the R-version of PopED.')
  if(opt_inds) stop('Optimization  of number of individuals in different groups is not yet implemented in the R-version of PopED.')
  if(opt_xt){ 
    #par <- c(par,poped.db$design$xt)
    # upper <- c(upper,poped.db$design_space$maxxt)
    # lower <- c(lower,poped.db$design_space$minxt)
    # par_grouping <- c(par_grouping,poped.db$design_space$G_xt)
    # par_type <- c(par_type,rep("xt",length(poped.db$design$xt)))
    par_dim$xt <- dim(poped.db$design$xt)
    if(is.null(poped.db$design_space$xt_space) && build_allowed_values){ 
      poped.db$design_space$xt_space <- cell(par_dim$xt)
    }
    # allowed_values <- c(allowed_values,poped.db$design_space$xt_space)
    
    for(i in 1:poped.db$design$m){
      if((poped.db$design$ni[i]!=0 && poped.db$design$groupsize[i]!=0)){
        par <- c(par,poped.db$design$xt[i,1:poped.db$design$ni[i]])
        upper <- c(upper,poped.db$design_space$maxxt[i,1:poped.db$design$ni[i]])
        lower <- c(lower,poped.db$design_space$minxt[i,1:poped.db$design$ni[i]])
        par_grouping <- c(par_grouping,poped.db$design_space$G_xt[i,1:poped.db$design$ni[i]])
        par_type <- c(par_type,rep("xt",length(poped.db$design$xt[i,1:poped.db$design$ni[i]])))
        allowed_values <- c(allowed_values,poped.db$design_space$xt_space[i,1:poped.db$design$ni[i]])
      }
    }
  }
  if(opt_a) { 
    par <- c(par,poped.db$design$a)
    upper <- c(upper,poped.db$design_space$maxa)
    lower <- c(lower,poped.db$design_space$mina)
    if(opt_xt){
      par_grouping <- c(par_grouping,poped.db$design_space$G_a + max(par_grouping)) 
    } else {
      par_grouping <- c(par_grouping,poped.db$design_space$G_a) 
    }
    par_type <- c(par_type,rep("a",length(poped.db$design$a)))
    par_dim$a <- dim(poped.db$design$a)
    if(is.null(poped.db$design_space$a_space) && build_allowed_values){ 
      poped.db$design_space$a_space <- cell(par_dim$a)
    }
    allowed_values <- c(allowed_values,poped.db$design_space$a_space)
    
  }
  if(opt_x) NULL # par <- c(par,poped.db$design$x)
  
  # continuous and discrete parameters
  npar <- max(c(length(lower),length(upper),length(allowed_values),length(par)))
  par_cat_cont <- rep("cont",npar)
  if(!is.null(allowed_values)){
    for(k in 1:npar){
      if(!is.na(allowed_values[[k]]) && length(allowed_values[[k]]>0)){
        par_cat_cont[k] <- "cat"          
      }
    }
  }
  
  # Parameter grouping
  par_df <- data.frame(par,par_grouping,upper,lower,par_type,par_cat_cont)
  par_df_unique <- NULL
  #allowed_values_full <- allowed_values 
  if(!all(!duplicated(par_df$par_grouping))){
    par_df_unique <- par_df[!duplicated(par_df$par_grouping),]
    par <- par_df_unique$par
    lower <- par_df_unique$lower
    upper <- par_df_unique$upper
    par_cat_cont <- par_df_unique$par_cat_cont
    allowed_values <- allowed_values[!duplicated(par_df$par_grouping)]
  }
  
  par_df_2 <- data.frame(par,upper,lower,par_cat_cont)
  par_fixed_index <- which(upper==lower)
  par_not_fixed_index <- which(upper!=lower)
  if(length(par_fixed_index)!=0){
    par <- par[-c(par_fixed_index)]
    lower <- lower[-c(par_fixed_index)]
    upper <- upper[-c(par_fixed_index)]
    par_cat_cont <- par_cat_cont[-c(par_fixed_index)]
    allowed_values <- allowed_values[-c(par_fixed_index)]
  }
  
  if(length(par)==0) stop("No design parameters have a design space to optimize")
  
  #------- create optimization function with optimization parameters first
  ofv_fun <- function(par,only_cont=F,...){
    
    if(length(par_fixed_index)!=0){
      par_df_2[par_not_fixed_index,"par"] <- par
      par <- par_df_2$par
    }
    
    if(!is.null(par_df_unique)){
      if(only_cont){ 
        par_df_unique[par_df_unique$par_cat_cont=="cont","par"] <- par
      } else {
        par_df_unique$par <- par
      }
      for(j in par_df_unique$par_grouping){
        par_df[par_df$par_grouping==j,"par"] <- par_df_unique[par_df_unique$par_grouping==j,"par"]
      }  
      
      #par_full[par_cat_cont=="cont"] <- par 
      par <- par_df$par
    } else if (only_cont){ 
      par_df[par_df$par_cat_cont=="cont","par"] <- par
      par <- par_df$par
    }
    xt <- NULL
    #if(opt_xt) xt <- matrix(par[par_type=="xt"],par_dim$xt)
    if(opt_xt){
      xt <- zeros(par_dim$xt)
      par_xt <- par[par_type=="xt"]
      for(i in 1:poped.db$design$m){
        if((poped.db$design$ni[i]!=0 && poped.db$design$groupsize[i]!=0)){
          xt[i,1:poped.db$design$ni[i]] <- par_xt[1:poped.db$design$ni[i]]
          par_xt <- par_xt[-c(1:poped.db$design$ni[i])]
        }
      }
    } 
    
    a <- NULL
    if(opt_a) a <- matrix(par[par_type=="a"],par_dim$a)
    
    # if(d_switch){
    #   FIM <- evaluate.fim(poped.db,xt=xt,a=a,...)
    #   ofv <- ofv_fim(FIM,poped.db,...)
    # } else{
    #   output <-calc_ofv_and_fim(poped.db,d_switch=d_switch,
    #                             ED_samp_size=ED_samp_size,
    #                             bLHS=bLHS,
    #                             use_laplace=use_laplace,
    #                             ofv_calc_type=ofv_calc_type,
    #                             fim.calc.type=fim.calc.type,
    #                             xt=xt,
    #                             a=a,
    #                             ...)
    #   
    #   FIM <- output$fim
    #   ofv <- output$ofv
    # }
    
    
    extra_args <- dots(...)
    extra_args$evaluate_fim <- FALSE
    
    output <- do.call(calc_ofv_and_fim,
                      c(list(
                        poped.db,d_switch=d_switch,
                        ED_samp_size=ED_samp_size,
                        bLHS=bLHS,
                        use_laplace=use_laplace,
                        ofv_calc_type=ofv_calc_type,
                        fim.calc.type=fim.calc.type,
                        xt=xt,
                        a=a,
                        ofv_fun = ofv_fun_user
                      ),
                      extra_args))
    
    
    # output <-calc_ofv_and_fim(poped.db,d_switch=d_switch,
    #                           ED_samp_size=ED_samp_size,
    #                           bLHS=bLHS,
    #                           use_laplace=use_laplace,
    #                           ofv_calc_type=ofv_calc_type,
    #                           fim.calc.type=fim.calc.type,
    #                           xt=xt,
    #                           a=a,
    #                           evaluate_fim = F,
    #                           ...)
    #FIM <- output$fim
    ofv <- output$ofv
    
    
    #ofv <- tryCatch(ofv_fim(FIM,poped.db,...), error = function(e) e)
    if(!is.finite(ofv) && ofv_calc_type==4){
      ofv <- -Inf 
    } else {
      if(!is.finite(ofv)) ofv <- 1e-15
      #if(!is.finite(ofv)) ofv <- NA
      #if(!is.finite(ofv)) ofv <- -Inf
    }
    
    #cat(ofv,"\n")
    return(ofv)
  }
  
  #------------ optimize
  if(!(fn=="")) sink(fn, append=TRUE, split=TRUE)
  
  iter <- 0
  stop_crit <- FALSE
  output$ofv <- dmf_init
  while(stop_crit==FALSE && iter < iter_max){
    ofv_init <- output$ofv
    iter=iter+1
    method_loop <- method
    if(loop_methods){
      cat("************* Iteration",iter," for all optimization methods***********************\n\n") 
    }
    
    while(length(method_loop)>0){
      cur_meth <- method_loop[1]
      method_loop <- method_loop[-1]
      if(cur_meth=="ARS"){
        cat("*******************************************\n")
        cat("Running Adaptive Random Search Optimization\n")
        cat("*******************************************\n")
        
        # handle control arguments
        con <- list(trace = trace, 
                    parallel=parallel,
                    parallel_type=parallel_type,
                    num_cores = num_cores)
        nmsC <- names(con)
        con[(namc <- names(control$ARS))] <- control$ARS
        #if (length(noNms <- namc[!namc %in% nmsC])) warning("unknown names in control: ", paste(noNms, collapse = ", "))
        
        output <- do.call(optim_ARS,c(list(par=par,
                                           fn=ofv_fun,
                                           lower=lower,
                                           upper=upper,
                                           allowed_values = allowed_values,
                                           maximize=maximize
                                           #par_df_full=par_df
        ),
        #par_grouping=par_grouping),
        con,
        ...))
        
      }
      if(cur_meth=="LS"){
        cat("*******************************************\n")
        cat("Running Line Search Optimization\n")
        cat("*******************************************\n")
        
        # handle control arguments
        con <- list(trace = trace, 
                    parallel=parallel,
                    parallel_type=parallel_type,
                    num_cores = num_cores)
        nmsC <- names(con)
        con[(namc <- names(control$LS))] <- control$LS
        #if (length(noNms <- namc[!namc %in% nmsC])) warning("unknown names in control: ", paste(noNms, collapse = ", "))
        
        output <- do.call(optim_LS,c(list(par=par,
                                          fn=ofv_fun,
                                          lower=lower,
                                          upper=upper,
                                          allowed_values = allowed_values,
                                          maximize=maximize
                                          #par_df_full=par_df
        ),
        #par_grouping=par_grouping),
        con,
        ...))
        
      }
      if(cur_meth=="BFGS"){
        
        cat("*******************************************\n")
        cat("Running L-BFGS-B Optimization\n")
        cat("*******************************************\n")
        
        if(all(par_cat_cont=="cat")){
          cat("\nNo continuous variables to optimize, L-BFGS-B Optimization skipped\n\n")
          next
        }
        
        if(trace) trace_optim=3
        if(is.numeric(trace)) trace_optim = trace
        #if(trace==2) trace_optim = 4
        #if(trace==3) trace_optim = 5
        #if(trace==4) trace_optim = 6
        
        # handle control arguments
        con <- list(trace=trace_optim)
        nmsC <- names(con)
        con[(namc <- names(control$BFGS))] <- control$BFGS
        fnscale=-1
        if(!maximize) fnscale=1
        if(is.null(con[["fnscale"]])) con$fnscale <- fnscale
        #if (length(noNms <- namc[!namc %in% nmsC])) warning("unknown names in control: ", paste(noNms, collapse = ", "))
        
        par_full <- par
        output <- optim(par=par[par_cat_cont=="cont"],
                        fn=ofv_fun,
                        gr=NULL,
                        #par_full=par_full,
                        only_cont=T,
                        lower=lower[par_cat_cont=="cont"],
                        upper=upper[par_cat_cont=="cont"],
                        method = "L-BFGS-B",
                        control=con)
        output$ofv <- output$value
        par_tmp <- output$par
        output$par <- par_full
        output$par[par_cat_cont=="cont"] <- par_tmp
        
        fprintf('\n')
        if(fn!="") fprintf(fn,'\n')
      }
      
      if(cur_meth=="GA"){
        
        cat("*******************************************\n")
        cat("Running Genetic Algorithm (GA) Optimization\n")
        cat("*******************************************\n")
        
        if (!requireNamespace("GA", quietly = TRUE)) {
          stop("GA package needed for this function to work. Please install it.",
               call. = FALSE)
        }
        
        if(all(par_cat_cont=="cat")){
          cat("\nNo continuous variables to optimize, GA Optimization skipped\n\n")
          next
        }
        
        # handle control arguments
        parallel_ga <- parallel
        if(!is.null(num_cores))  parallel_ga <- num_cores
        if(!is.null(parallel_type))  parallel_ga <- parallel_type
        
        con <- list(parallel=parallel_ga)
        dot_vals <- dots(...)
        if(is.null(dot_vals[["monitor"]]) && packageVersion("GA")>="3.0.2") con$monitor <- GA::gaMonitor2
        
        nmsC <- names(con)
        con[(namc <- names(control$GA))] <- control$GA
        #if (length(noNms <- namc[!namc %in% nmsC])) warning("unknown names in control: ", paste(noNms, collapse = ", "))
        
        par_full <- par
        ofv_fun_2 <- ofv_fun
        if(!maximize) {
          ofv_fun_2 <- function(par,only_cont=F,...){
            -ofv_fun(par,only_cont=F,...) 
          }
        }
        output_ga <- do.call(GA::ga,c(list(type = "real-valued", 
                                           fitness = ofv_fun_2,
                                           #par_full=par_full,
                                           only_cont=T,
                                           min=lower[par_cat_cont=="cont"],
                                           max=upper[par_cat_cont=="cont"],
                                           suggestions=par[par_cat_cont=="cont"]),
                                      #allowed_values = allowed_values),
                                      con,
                                      ...))
        
        
        output$ofv <- output_ga@fitnessValue
        if(!maximize) output$ofv <- -output$ofv
        
        
        output$par <- output_ga@solution
        
        par_tmp <- output$par
        output$par <- par_full
        output$par[par_cat_cont=="cont"] <- par_tmp
        
        fprintf('\n')
        if(fn!="") fprintf(fn,'\n')
      }
      par <- output$par
    }
    
    if(!loop_methods){
      stop_crit <- TRUE
    } else {
      cat("*******************************************\n")
      cat("Stopping criteria testing\n")
      cat("(Compare between start of iteration and end of iteration)\n")
      cat("*******************************************\n")
      
      # relative difference
      rel_diff <- (output$ofv - ofv_init)/ofv_init
      abs_diff <- (output$ofv - ofv_init)
      fprintf("Difference in OFV:  %.3g\n",abs_diff)
      fprintf("Relative difference in OFV:  %.3g%%\n",rel_diff*100)
      
      # efficiency
      
        
      eff <- efficiency(ofv_init, output$ofv, poped.db)
      fprintf("Efficiency: \n  (%s) = %.5g\n",attr(eff,"description"),eff)
      #cat("Efficiency: \n  ", attr(eff,"description"), sprintf("%.5g",eff), "\n")
      #if(eff<=stop_crit_eff) stop_crit <- TRUE
      
      #cat("eff: ",sprintf("%.3g",(output$ofv - ofv_init)/p), "\n")
      #cat("eff: ",sprintf("%.3g",(exp(output$ofv)/exp(ofv_init))^(1/p)), "\n")
      
      
      compare <-function(crit,crit_stop,maximize,inv=FALSE,neg=FALSE,text=""){
        
        if(is.null(crit_stop)){
          #cat("  Stopping criteria not defined\n")
          return(FALSE)
        }
        cat("\n",text,"\n")
        if(is.nan(crit)){
          fprintf("  Stopping criteria using 'NaN' as a comparitor cannot be used\n")
          return(FALSE)
        } 
        
        comparitor <- "<="
        if(!maximize) comparitor <- ">="
        if(inv) crit_stop <- 1/crit_stop
        if(neg) crit_stop <- -crit_stop
        fprintf("  Is (%0.5g %s %0.5g)? ",crit,comparitor,crit_stop)
        res <- do.call(comparitor,list(crit,crit_stop))
        if(res) cat("  Yes.\n  Stopping criteria achieved.\n")
        if(!res) cat("  No.\n  Stopping criteria NOT achieved.\n")
        return(res)
        #if(maximize) cat("Efficiency stopping criteria (lower limit) = ",crit_stop, "\n")
        #if(!maximize) cat("Efficiency stopping criteria (upper limit) = ",1/crit_stop, "\n")
        
        #if(maximize) return(crit <= crit_stop)
        #if(!maximize) return(crit >= 1/crit_stop)
      } 
      
      if(all(is.null(c(stop_crit_eff,stop_crit_rel,stop_crit_diff)))){
        cat("No stopping criteria defined")
      } else {
        
        
        stop_eff <- compare(eff,stop_crit_eff,maximize,inv=!maximize,
                            text="Efficiency stopping criteria:")
        
        stop_abs <- compare(abs_diff,stop_crit_diff,maximize,neg=!maximize,
                            text="OFV difference stopping criteria:")
        
        stop_rel <- compare(rel_diff,stop_crit_rel,maximize,neg=!maximize,
                            text="Relative OFV difference stopping criteria:")
        
        if(stop_eff || stop_rel || stop_abs) stop_crit <- TRUE
        
        if(stop_crit){
          cat("\nStopping criteria achieved.\n")
        } else {
          cat("\nStopping criteria NOT achieved.\n")
        }
        cat("\n")
      }
    }
    
  } # end of total loop 
  
  if(!(fn=="")) sink()
  
  # add the results into a poped database 
  # expand results to full size 
  if(length(par_fixed_index)!=0){
    par_df_2[par_not_fixed_index,"par"] <- par
    par <- par_df_2$par
  }
  if(!is.null(par_df_unique)){
    par_df_unique$par <- par
    for(j in par_df_unique$par_grouping){
      par_df[par_df$par_grouping==j,"par"] <- par_df_unique[par_df_unique$par_grouping==j,"par"]
    }  
  } else {
    par_df$par <- par
  }  
  
  #poped.db$design$ni <- ni
  #if(opt_xt) poped.db$design$xt[,]=matrix(par_df[par_type=="xt","par"],par_dim$xt)
  if(opt_xt){
    xt <- zeros(par_dim$xt)
    par_xt <- par_df[par_type=="xt","par"]
    for(i in 1:poped.db$design$m){
      if((poped.db$design$ni[i]!=0 && poped.db$design$groupsize[i]!=0)){
        xt[i,1:poped.db$design$ni[i]] <- par_xt[1:poped.db$design$ni[i]]
        par_xt <- par_xt[-c(1:poped.db$design$ni[i])]
      }
    }
    poped.db$design$xt[,]=xt[,]
  }
  
  if(opt_a) poped.db$design$a[,]=matrix(par_df[par_type=="a","par"],par_dim$a)
  #   if((!isempty(x))){
  #     poped.db$design$x[1:size(x,1),1:size(x,2)]=x
  #     #poped.db$design$x <- x
  #   }
  #   if((!isempty(a))){
  #     poped.db$design$a[1:size(a,1),1:size(a,2)]=a
  #     #poped.db$design$a <- a
  #   }
  
  #--------- Write results
  #if((trflag)){
  #  if(footer_flag){
  #FIM <- evaluate.fim(poped.db,...)
  
  # if(d_switch){
  #   FIM <- evaluate.fim(poped.db,...)
  # } else{
  #   out <-calc_ofv_and_fim(poped.db,d_switch=d_switch,
  #                          ED_samp_size=ED_samp_size,
  #                          bLHS=bLHS,
  #                          use_laplace=use_laplace,
  #                          ofv_calc_type=ofv_calc_type,
  #                          fim.calc.type=fim.calc.type,
  #                          ...)
  #   
  #   FIM <- out$fim
  # }
  
  FIM <-calc_ofv_and_fim(poped.db,
                         ofv=output$ofv,
                         fim=0, 
                         d_switch=d_switch,
                         ED_samp_size=ED_samp_size,
                         bLHS=bLHS,
                         use_laplace=use_laplace,
                         ofv_calc_type=ofv_calc_type,
                         fim.calc.type=fim.calc.type,
                         ofv_fun = ofv_fun_user,
                         ...)[["fim"]]
  
  blockfinal(fn=fn,fmf=FIM,
             dmf=output$ofv,
             groupsize=poped.db$design$groupsize,
             ni=poped.db$design$ni,
             xt=poped.db$design$xt,
             x=poped.db$design$x,
             a=poped.db$design$a,
             model_switch=poped.db$design$model_switch,
             poped.db$parameters$param.pt.val$bpop,
             poped.db$parameters$param.pt.val$d,
             poped.db$parameters$docc,
             poped.db$parameters$param.pt.val$sigma,
             poped.db,
             fmf_init=fmf_init,
             dmf_init=dmf_init,
             ...)
  
  
  #  }
  #}
  
  return(invisible(list( ofv= output$ofv, FIM=FIM, poped.db = poped.db ))) 
}

#' Compute efficiency.
#' 
#' Efficiency calculation between two designs.
#' 
#' 
#' @param ofv_init An initial objective function
#' @param ofv_final A final objective function.
#' @param npar The number of parameters to use for normalization.
#' @param poped_db a poped database
#' @inheritParams ofv_fim
#' @inheritParams poped_optim
#' @inheritParams create.poped.database
#' 
#' @return The specified efficiency value depending on the ofv_calc_type.  
#' The attribute "description" tells you how the calculation was made 
#' \code{attr(return_vale,"description")}
#' 
#' @family FIM
#' 
#' 
## @example tests/testthat/examples_fcn_doc/warfarin_optimize.R
## @example tests/testthat/examples_fcn_doc/examples_ofv_criterion.R
#' 
#' @export

efficiency <- function(ofv_init, ofv_final, poped_db,
                       npar = get_fim_size(poped_db),
                       ofv_calc_type=poped_db$settings$ofv_calc_type,
                       ds_index = poped_db$parameters$ds_index) {
  
  
  eff = ofv_final/ofv_init
  attr(eff,"description") <- "ofv_final / ofv_init"
  
  if((ofv_calc_type==1) ){#D-Optimal Design
    eff = eff^(1/npar)
    attr(eff,"description") <- "(ofv_final / ofv_init)^(1/n_parameters)"
  }
  if((ofv_calc_type==4) ){#lnD-Optimal Design
    eff = (exp(ofv_final)/exp(ofv_init))^(1/npar)
    attr(eff,"description") <- "(exp(ofv_final) / exp(ofv_init))^(1/n_parameters)"
    
  }
  # if((ofv_calc_type==2) ){#A-Optimal Design
  #   eff=ofv_f/npar
  # }
  # 
  # if((ofv_calc_type==3) ){#S-Optimal Design
  #   stop(sprintf('Criterion for S-optimal design not implemented yet'))
  # }
  # 
  if((ofv_calc_type==6) ){#Ds-Optimal design
    eff = eff^(1/sum(ds_index))
    attr(eff,"description") <- "(ofv_final / ofv_init)^(1/sum(interesting_parameters))"
    
  }   
  
  return( eff ) 
}

