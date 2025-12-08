#' Plots, or returns a plot, displaying a full alignment output
#'
#' @param output An output dataframe created by align()
#' @param fontSize The desired font size of the text
#' @param regimenCombine Allowed number of days between two instances of the same regimen before
#' @param returnDat A toggle to also return a processed data object
#' @param returnDrugs A toggle to indicate whether drugs should be returned by processing,
#' in addition to regimens
#' @return regPlot - A ggplot object
#' @export
plotOutput <- function(output, known_drugs = NULL){
  # Create dataframe for drugs. 
  # Use patient drug record to create cumulative times
  df = output %>%
      select(person_id = personID, seq = DrugRecord_full) %>% 
      distinct() %>% 
      separate_rows(seq, sep = ";") %>%
      separate(seq, into = c("time", 'component')) %>%
      filter(time != "") %>%
      group_by(person_id) %>%
      mutate(
          time_start = cumsum(as.integer(time)),
          time_end = time_start + 1,
          #time_cumsum = cumsum(time),
          case = "drugs",
          person_id = as.character(person_id)
      ) %>%
      arrange(time)

  # Add patient_name if it does not exists
  # It is used to facet plots so we can compare multiple patients
  if(!"patient_name" %in% names(output)) {
      output$patient_name = output$personID
  }

  # Create dataframe for regimens
  df = output %>%
      select(
          person_id = personID,
          patient_name,
          component,
          time_start = t_start,
          time_end = t_end,
          adjustedS
      ) %>%
      mutate(time_end = ifelse(time_start == time_end, time_end + 1, time_end)) %>% 
      mutate(case = "regimen", 
            adjustedS = round(adjustedS, 2)) %>%
      bind_rows(df) %>%
      mutate(component = fct_reorder(component, time_start))

  # Get unique components for drugs and regimens
  patient_components <- unique(df$component[df$case == "drugs"])
  regimen_components <- unique(df$component[df$case == "regimen"])

  patient_components = as.character(patient_components)
  regimen_components = as.character(regimen_components)
  # Generate dynamic color palettes
  if(length(patient_components) < 10) {
      patient_colors <- setNames(brewer.pal(length(patient_components), "Set1"), patient_components)
  } else {
      patient_colors <- setNames(viridis(length(patient_components), option = "D"), patient_components)
  }
  regimen_colors <- setNames(brewer.pal(length(regimen_components), "Paired"), regimen_components)
  # Combine color mappings
  colors <- c(patient_colors, regimen_colors)
  # Create separate aesthetics for drugs and regimens
  df$patient_components_col <- ifelse(df$case == "drugs", as.character(df$component), NA)
  df$regimen_components_col <- ifelse(df$case == "regimen", as.character(df$component), NA)

  # Compute midpoints
  df$mid_x <- (df$time_start + df$time_end) / 2

  p = df %>%
      ggplot() +
      geom_segment(
          aes(
              x = time_start,
              xend = time_end,
              y = component,
              yend = component,
              color = patient_components_col
          ),
          linewidth = 2,
          na.rm = TRUE
      ) +
      geom_segment(
          aes(
              x = time_start,
              xend = time_end,
              y = component,
              yend = component,
              color = regimen_components_col
          ),
          linewidth = 2,
          na.rm = TRUE
      ) +
      geom_text(aes(x = mid_x, y = component, label = adjustedS), vjust = -0.5, size = 3) +
      geom_point(aes(x = time_start, y = component, color = patient_components_col)) +
      facet_grid(
          cols = vars(person_id),
          rows = vars(case),
          scale = "free_y"
      ) +
      scale_color_manual(
          name = "patient",
          values = colors,
          na.translate = FALSE,
          guide = guide_legend(order = 1)
      ) +
      scale_color_manual(
          name = "regimen",
          values = colors,
          na.translate = FALSE
      ) +
      guides(color = guide_legend(order = 3, override.aes = list(size = 3))) +
      labs(x = "Time", y = "Component", title = "Time Intervals per Component") +
      theme_bw() +
      theme(legend.position = "none",
            axis.text.y = element_markdown()) + # Move legends below
      ggtitle(label = paste("Patient", unique(df$patient_name))) +
      scale_y_discrete(labels = function(x) {
          ifelse(!x %in% known_drugs & !x %in% df$component, 
                paste0("**", x, "**"), x)
      })

    return(p)
}

#' Plot a full alignment output utilising an already
#' processed output
#' @param processedAll An output dataframe created by processAlignments
#' @param fontSize The desired font size of the text
#' @return regPlot - A ggplot object
#' @export
plotProcesssed <- function(processedAll,
                           fontSize = 2.5){

  plot <- processedAll

  ord <- unique(plot[order(plot$regimen,plot$t_start),]$component)

  plot$component <- factor(plot$component, levels = ord)

  breaks <- seq(-14, max(plot$t_end)+5, 1)
  tickLabels <- as.character(breaks)
  tickLabels[!(breaks %% 28 == 0)] <- ''

  overlapLines <- as.data.frame(matrix(ncol = 5))
  overlapT <- plot[plot$regimen == "Yes",]
  j <- 1

  if(dim(overlapT)[1] > 1){
    for(i in c(1:(dim(overlapT)[1]-1))){
      if(overlapT[i,]$component==overlapT[i+1,]$component){
        overlapLines[j,] <- c(as.numeric(overlapT[i,]$t_end),
                              as.numeric(overlapT[i+1,]$t_start),
                              as.character(overlapT[i,]$component),
                              "Line","0")
        j <- j + 1
      }
    }
  }

  colnames(overlapLines) <- colnames(plot)[1:5]
  overlapLines$t_start <- as.numeric(overlapLines$t_start)
  overlapLines$t_end <- as.numeric(overlapLines$t_end)
  overlapLines$component <- factor(overlapLines$component, levels = ord)

  plot[plot$regimen=="Yes",]$t_start <- plot[plot$regimen=="Yes",]$t_start - 2
  plot[plot$regimen=="Yes",]$t_end <- plot[plot$regimen=="Yes",]$t_end + 2

  p1 <- ggplot2::ggplot(plot, ggplot2::aes(x = .data$t_start)) +
    ggplot2::geom_rect(data = plot[plot$regimen=="Yes",],
                           ggplot2::aes(ymin = as.numeric(.data$component)-0.3,
                                        ymax = as.numeric(.data$component)+0.3,
                                        xmin = .data$t_start,
                                        xmax = .data$t_end, fill = .data$component)) +
    ggplot2::geom_text(size = 3,
                       data = plot[plot$regimen=="Yes",],
                       ggplot2::aes(x = (.data$t_start+.data$t_end)/2,
                                    y = as.numeric(.data$component)+0.5,
                                    label=paste("S: ", round(100*as.numeric(.data$adjustedS),0)))) +
    ggplot2::geom_point(data = plot[plot$regimen=="No",], size = 3,
                        ggplot2::aes(x= .data$t_start,y= as.numeric(.data$component),
                                     fill = .data$component), shape = 21) +
    ggplot2::scale_y_continuous(labels = stringi::stri_trans_totitle(ord), breaks = seq(1,length(ord))) +
    ggplot2::scale_x_continuous(breaks = seq(0,max(plot$t_end),28)) +
    ggplot2::theme(panel.background = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_line(colour = "grey95"),
                   legend.position = "none") +
    ggplot2::xlab("") + ggplot2::ylab("") +
    ggplot2::geom_segment(data = overlapLines, ggplot2::aes(y = as.numeric(.data$component),
                                                            yend = as.numeric(.data$component),
                                                            x = .data$t_start,
                                                            xend = .data$t_end,
                                                            colour = .data$component),
                          linetype = 2, lwd = 1) +
    ggplot2::scale_fill_viridis_d(drop=F) +
    ggplot2::scale_color_viridis_d(drop=F) +
    ggplot2::geom_hline(linetype = 3,
                        yintercept = table(plot[!duplicated(plot$component),]$regimen == "No")[2]+0.5)

  return(p1)
}

#' Plots a plot displaying the observed score distribution for a given regimen, or two given regimens
#' processed output
#' @param processedAll An output dataframe created by processAlignments
#' @param regimen1 A regimen of interest
#' @param regimen2 An optional regimen of interest for comparison
#' @return regPlot - A ggplot object
#' @export
plotScoreDistribution <- function(regimen1,regimen2=NA,processedAll){

  scoreDistibution_All <- processedAll[,c("component","adjustedS")]
  colnames(scoreDistibution_All) <- c("regName","adjustedS")

  if(is.na(regimen2)){

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen1),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)+sd(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)-sd(score_plot$adjustedS)
                              )
    )

    ggplot2::ggplot(score_plot, ggplot2::aes(x=adjustedS)) +
      ggplot2::geom_histogram(binwidth = 0.01, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen1)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Adjusted Score") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$adjustedS),2),"\n","Interquartile Range: ",signif(IQR(score_plot$adjustedS),3),sep=""))

  } else {

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen1),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)+sd(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)-sd(score_plot$adjustedS)
                              )
    )

    p1 <- ggplot2::ggplot(score_plot, ggplot2::aes(x=adjustedS)) +
      ggplot2::geom_histogram(binwidth = 0.01, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen1)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Adjusted Score") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$adjustedS),2),"\n","Interquartile Range: ",signif(IQR(score_plot$adjustedS),3),sep=""))

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen2),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)+sd(score_plot$adjustedS),
                                        mean(score_plot$adjustedS)-sd(score_plot$adjustedS)
                              )
    )

    p2 <- ggplot2::ggplot(score_plot, ggplot2::aes(x=adjustedS)) +
      ggplot2::geom_histogram(binwidth = 0.01, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen2)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Adjusted Score") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$adjustedS),2),"\n","Interquartile Range: ",signif(IQR(score_plot$adjustedS),3),sep=""))

    gridExtra::grid.arrange(p1,p2,ncol=1)


  }

}


#' Plots a plot displaying the observed regimen length distribution for a given regimen, or two given regimens
#' processed output
#' @param processedAll An output dataframe created by processAlignments
#' @param regimen1 A regimen of interest
#' @param regimen2 An optional regimen of interest for comparison
#' @return regPlot - A ggplot object
#' @export
plotRegimenLengthDistribution <- function(regimen1,regimen2=NA,processedAll){

  scoreDistibution_All <- processedAll[,c("component","regLength")]
  colnames(scoreDistibution_All) <- c("regName","regLength")

  if(is.na(regimen2)){

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen1),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$regLength),
                                        mean(score_plot$regLength)+sd(score_plot$regLength),
                                        mean(score_plot$regLength)-sd(score_plot$regLength)
                              )
    )

    ggplot2::ggplot(score_plot, ggplot2::aes(x=.data$regLength)) +
      ggplot2::geom_histogram(binwidth = 5, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen1)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Regimen Length") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$regLength),2),"\n","Interquartile Range: ",signif(IQR(score_plot$regLength),3),sep=""))

  } else {

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen1),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$regLength),
                                        mean(score_plot$regLength)+sd(score_plot$regLength),
                                        mean(score_plot$regLength)-sd(score_plot$regLength)
                              )
    )

    p1 <- ggplot2::ggplot(score_plot, ggplot2::aes(x=.data$regLength)) +
      ggplot2::geom_histogram(binwidth = 5, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen1)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Regimen Length") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$regLength),2),"\n","Interquartile Range: ",signif(IQR(score_plot$regLength),3),sep=""))

    score_plot <- scoreDistibution_All[stringr::str_to_lower(scoreDistibution_All$regName) == stringr::str_to_lower(regimen2),]
    score_stats <- data.frame(statistic = c("mean","sd_upper","sd_lower"),
                              linetype = c("Mean","+/- SD","+/- SD"),
                              value = c(mean(score_plot$regLength),
                                        mean(score_plot$regLength)+sd(score_plot$regLength),
                                        mean(score_plot$regLength)-sd(score_plot$regLength)
                              )
    )

    p2 <- ggplot2::ggplot(score_plot, ggplot2::aes(x=.data$regLength)) +
      ggplot2::geom_histogram(binwidth = 5, color="darkblue",fill="grey80") +
      ggplot2::geom_density(alpha=.4, fill="lightblue") +
      ggplot2::geom_vline(data=score_stats, ggplot2::aes(xintercept=.data$value,linetype=.data$linetype), size=1, col="lightblue3") +
      ggplot2::scale_linetype_manual(name = "Stat.", breaks=c("Mean", "+/- SD"), values = c("solid","dashed")) +
      ggplot2::ggtitle(paste(regimen2)) +
      ggplot2::xlab("Density") +
      ggplot2::ylab("Adjusted Score") +
      ggplot2::theme_minimal() +
      ggplot2::labs(caption = paste("Median: ",signif(median(score_plot$regLength),2),"\n","Interquartile Range: ",signif(IQR(score_plot$regLength),3),sep=""))

    gridExtra::grid.arrange(p1,p2,ncol=1)


  }

}

#' Plots a plot displaying the frequency of the top N most frequent regimens
#' @param processedAll An output dataframe created by processAlignments
#' @param N The number of top rows to plot
#' @export
plotFrequency <- function(processedAll, N = 10){

  freqPlot <- as.data.frame(table(processedAll$component)/sum(table(processedAll$component)))
  freqPlot <- freqPlot[order(freqPlot$Freq, decreasing = T),]

  if(dim(freqPlot)[1] < N){
    N <- dim(freqPlot)[1]
  }

  freqPlot <- freqPlot[1:N,]
  freqPlot$Var1 <- factor(freqPlot$Var1, levels = freqPlot[order(freqPlot$Freq, decreasing = F),]$Var1)

  names <- freqPlot$Var1

  cols <- ggsci::pal_jco()(10)
  cols <- c(cols,ggsci::pal_jama()(7))

  if(N < 18){
    names(cols) <- names[sample(x = c(1:17))]
  } else{
    cols <- rep(cols,N)
    names(cols) <- names[sample(x = c(1:N))]
  }

  ggplot2::ggplot(freqPlot, ggplot2::aes(y=.data$Var1,x=.data$Freq,fill=.data$Var1)) +
    ggplot2::geom_bar(stat="identity") +
    ggplot2::scale_fill_manual(values = cols) +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "none")
}


#' Plots a plot displaying the ERA frequency of the top N most frequent eras
#' @param processedEras An output dataframe created by calculateEras
#' @param N The number of top rows to plot
#' @export
plotErasFrequency <- function(processedEras, N = 10){
  firstLine <- processedEras[processedEras$First_Line==1,]
  firstLine_Tab <- as.data.frame(table(firstLine$component))

  secondLine <- processedEras[processedEras$Second_Line==1,]
  secondLine_Tab <- as.data.frame(table(secondLine$component))

  firstLine_Tab <- firstLine_Tab[order(firstLine_Tab$Freq, decreasing = T),]
  firstLine_Tab$Freq <- firstLine_Tab$Freq/sum(firstLine_Tab$Freq)

  firstLine_Tab.p <- firstLine_Tab[1:N,]

  firstLine_Tab.p$Var1 <- stringr::str_wrap(firstLine_Tab.p$Var1, width = 18)

  firstLine_Tab.p$Var1 <- factor(firstLine_Tab.p$Var1,
                                 levels = firstLine_Tab.p[order(firstLine_Tab.p$Freq, decreasing = F),]$Var1)

  secondLine_Tab <- secondLine_Tab[order(secondLine_Tab$Freq, decreasing = T),]
  secondLine_Tab$Freq <- secondLine_Tab$Freq/sum(secondLine_Tab$Freq)

  secondLine_Tab.p <- secondLine_Tab[1:N,]

  secondLine_Tab.p$Var1 <- stringr::str_wrap(secondLine_Tab.p$Var1, width = 18)

  secondLine_Tab.p$Var1 <- factor(secondLine_Tab.p$Var1,
                                  levels = secondLine_Tab.p[order(secondLine_Tab.p$Freq, decreasing = F),]$Var1)


  names <- as.character(unique(c(firstLine_Tab.p$Var1,secondLine_Tab.p$Var1)))

  cols <- ggsci::pal_jco()(10)
  cols <- c(cols,ggsci::pal_jama()(7))

  if(N < 18){
    names(cols) <- names[sample(x = c(1:17))]
  } else{
    cols <- rep(cols,N)
    names(cols) <- names[sample(x = c(1:N))]
  }

  fline <- ggplot2::ggplot(na.omit(firstLine_Tab.p), ggplot2::aes(x=.data$Var1,y=.data$Freq,fill=.data$Var1,col="black")) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::theme(panel.background = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_line(colour = "grey95"),
                   legend.position = "none") +
    ggplot2::scale_fill_manual(values = cols) +
    ggplot2::scale_color_manual(values = c("black" = "black")) +
    ggplot2::ylab("Frequency") + ggplot2::xlab("") + ggplot2::ggtitle("First Regimen") +
    ggplot2::coord_flip() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(size = 14),
      axis.text.y = ggplot2::element_text(size = 15))

  sline <- ggplot2::ggplot(na.omit(secondLine_Tab.p), ggplot2::aes(x=.data$Var1,y=.data$Freq,fill=.data$Var1,col="black")) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::theme(panel.background = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_line(colour = "grey95"),
                   legend.position = "none") +
    ggplot2::scale_fill_manual(values = cols) +
    ggplot2::scale_color_manual(values = c("black" = "black")) +
    ggplot2::ylab("Frequency") + ggplot2::xlab("") + ggplot2::ggtitle("Second Regimen") +
    ggplot2::coord_flip() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(size = 14),
      axis.text.y = ggplot2::element_text(size = 15))

  gridExtra::grid.arrange(fline,sline,ncol=2)
}

#' Plots a sankey diagram displaying the flow between first, second and third regimen eras
#' @param processedEras An output dataframe created by calculateEras
#' @param regGroups A dataframe indicating how to group regimens
#' @param saveLocation A file directory location where files may be saved
#' @param fileName A filename prefix for saved files
#' @export
plotSankey <- function(processedEras, regGroups, saveLocation = NA, fileName = "Network"){

  if(is.na(saveLocation)){
    saveLocation <- here::here()
  }

  firstLine <- processedEras[processedEras$First_Line==1,]
  firstLine_Tab <- as.data.frame(table(firstLine$component))

  secondLine <- processedEras[processedEras$Second_Line==1,]
  secondLine_Tab <- as.data.frame(table(secondLine$component))

  thirdLine <- processedEras[processedEras$Other==1,]
  thirdLine_Tab <- as.data.frame(table(thirdLine$component))

  sankey_first <- firstLine[,c(6,3)]
  sankey_sec <- secondLine[,c(6,3)]
  sankey_third <- thirdLine[,c(6,3)]

  colnames(sankey_first) <- c("personID","Var1")
  colnames(sankey_sec) <- c("personID","Var1")
  colnames(sankey_third) <- c("personID","Var1")

  colnames(regGroups) <- c("Var1","regGroup")

  sankey_first <- merge(sankey_first,regGroups,by="Var1")[,c(2,3)]
  sankey_sec <- merge(sankey_sec,regGroups,by="Var1")[,c(2,3)]
  sankey_third <- merge(sankey_third,regGroups,by="Var1")[,c(2,3)]

  colnames(sankey_first) <- c("personID","First Line")
  colnames(sankey_sec) <- c("personID","Second Line")
  colnames(sankey_third) <- c("personID","Subsequent Lines")

  sankey_all <- merge(merge(sankey_first,sankey_sec,all = T),sankey_third,all=T)
  sankey_all <- sankey_all[!duplicated(sankey_all$personID),]

  sankey_all[is.na(sankey_all$`Second Line`),]$`Second Line` <- ""
  sankey_all[is.na(sankey_all$`Subsequent Lines`),]$`Subsequent Lines` <- ""

  tt1 <- as.data.frame(table(reshape2::melt(sankey_all[,c(2,3)],
                                  id.vars = c("First Line","Second Line"), na.rm = F)))

  tt2 <- as.data.frame(table(reshape2::melt(sankey_all[,c(3,4)],
                                  id.vars = c("Second Line","Subsequent Lines"), na.rm = F)))


  tt1$First.Line <- as.character(tt1$First.Line)
  tt1$Second.Line <- as.character(tt1$Second.Line)
  tt2$Second.Line <- as.character(tt2$Second.Line)
  tt2$Subsequent.Lines <- as.character(tt2$Subsequent.Lines)

  tt1 <- tt1[!tt1$First.Line==tt1$Second.Line,]
  tt2 <- tt2[!tt2$Second.Line==tt2$Subsequent.Lines,]

  tt1$First.Line <- paste(tt1$First.Line,"(1st)",sep=" ")
  tt1$Second.Line <- paste(tt1$Second.Line,"(2nd)",sep=" ")

  tt2$Second.Line <- paste(tt2$Second.Line,"(2nd)",sep=" ")
  tt2$Subsequent.Lines <- paste(tt2$Subsequent.Lines,"(3rd)",sep=" ")

  colnames(tt1) <- c("source","target","value")
  colnames(tt2) <- c("source","target","value")

  links <- rbind(tt1,tt2)

  links <- links[!links$target %in% c(" (2nd)"," (3rd)"),]
  links <- links[!links$source %in% c(" (2nd)"," (3rd)"),]

  nodes <- data.frame(
    name=c(as.character(links$source),
           as.character(links$target)) %>% unique()
  )

  links$IDsource <- match(links$source, nodes$name)-1
  links$IDtarget <- match(links$target, nodes$name)-1

  p <- networkD3::sankeyNetwork(Links = links, Nodes = nodes,
                     Source = "IDsource", Target = "IDtarget",
                     Value = "value", NodeID = "name",
                     sinksRight=FALSE, width = 2200, height = 1000,
                     fontSize = 28, fontFamily = "calibri")

  networkFile <- paste(saveLocation,"/",fileName,".html",sep="")

  networkD3::saveNetwork(p, file = networkFile)

  webshot::webshot(url = networkFile, file = paste(saveLocation,"/",fileName,".png",sep=""), vwidth = 2200, vheight = 1000)


  }
