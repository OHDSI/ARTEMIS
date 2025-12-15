#' Plots a full alignment output
#' For each patient 
#' @param pa A patient alignment dataframe created by align()
#' @return plot - A ggplot object
#' @export
#' @importFrom ggplot2 ggplot aes geom_segment geom_text geom_point facet_grid
#' @importFrom ggplot2 scale_color_manual guides labs theme_bw theme ggtitle scale_y_discrete guide_legend
#' @importFrom ggtext element_markdown
#' @importFrom dplyr filter select distinct arrange mutate bind_rows group_by arrange vars
#' @importFrom forcats fct_reorder
#' @importFrom tidyr separate_rows separate 
#' @importFrom RColorBrewer brewer.pal
plotAlignment <- function(pa, known_drugs = NULL){
  # Add patient_name if it does not exists
  # It is used to facet plots so we can compare multiple patients
  if(!"patient_name" %in% names(pa)) {
      pa$patient_name = pa$personID
  }

  if (length(unique(pa$patient_name)) > 1) {
    cli::cat_bullet(
            paste("Multiple patients detected, only the first one will be plotted.", sep = ""),
            bullet_col = "yellow",
            bullet = "info"
        )
  }

  pa = pa %>%
      filter(patient_name == pa$patient_name[1])

  # Create dataframe for drugs. 
  # Use patient drug record to create cumulative times
  df = pa %>%
      select(person_id = personID, seq = DrugRecord_full) %>% 
      distinct() %>% 
      separate_rows(seq, sep = ";") %>%
      separate(seq, into = c("time", 'component')) %>%
      filter(time != "") %>%
      group_by(person_id) %>%
      mutate(
          t_start = cumsum(as.integer(time)),
          t_end = t_start + 1,
          case = "drugs",
          person_id = as.character(person_id)
      ) %>%
      arrange(time)

  # Create dataframe for regimens
  df = pa %>%
      select(
          person_id = personID,
          patient_name,
          component,
          t_start,
          t_end,
          adjustedS
      ) %>%
      mutate(t_end = ifelse(t_start == t_end, t_end + 1, t_end)) %>% 
      mutate(case = "regimen", 
            adjustedS = round(adjustedS, 2)) %>%
      bind_rows(df) %>%
      mutate(component = fct_reorder(component, t_start))

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
  df$mid_x <- (df$t_start + df$t_end) / 2

  p = df %>%
      ggplot() +
      geom_segment(
          aes(
              x = t_start,
              xend = t_end,
              y = component,
              yend = component,
              color = patient_components_col
          ),
          linewidth = 2,
          na.rm = TRUE
      ) +
      geom_segment(
          aes(
              x = t_start,
              xend = t_end,
              y = component,
              yend = component,
              color = regimen_components_col
          ),
          linewidth = 2,
          na.rm = TRUE
      ) +
      geom_text(aes(x = mid_x, y = component, label = adjustedS), vjust = -0.5, size = 3) +
      geom_point(aes(x = t_start, y = component, color = patient_components_col)) +
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


#' Adjusted Score distribution plot
#' Plot histogram and density of adjusted scores for regimens, or top regimens by frequency
#' processed output
#' @param pa Patients alignments dataframe created by raw or processAlignments
#' @param components A set of regimens of interest
#' @param top_n Top n most frequent regimens to plot. Ignored if components provided. Default is 6
#' @return plot - A ggplot object
#' @export
#' @importFrom ggplot2 ggplot aes geom_histogram geom_density geom_vline scale_linetype_manual ggtitle xlab ylab theme_minimal labs facet_wrap
#' @importFrom dplyr filter group_by reframe
plotScoreDistribution <- function(pa, components = NULL, top_n = 6) {
  # If component column does not exist, create it from regName
  if(!"component" %in% names(pa) & "regName" %in% names(pa)){
    pa$component <- pa$regName
  }

  if (is.null(components)) {
    # take most prevelant   
    top_components <- table(pa$component) %>%
      sort() %>% 
      tail(n = top_n) %>% 
      names()
  } else {
    top_components <- components
  }
  
  sp <- pa %>% 
      filter(component %in% top_components)

  score_stats <- sp %>% 
    group_by(component) %>% 
    reframe(statistic = c("mean","sd_upper","sd_lower"),
            linetype = c("Mean","+/- SD","+/- SD"),
            value = c(mean(adjustedS),
                      mean(adjustedS) + sd(adjustedS),
                      mean(adjustedS) - sd(adjustedS)
            )
    )
      
  p <- ggplot(sp, aes(x = adjustedS)) +
      geom_histogram(binwidth = 0.01,
                    color = "darkblue",
                    fill = "grey80") +
      geom_density(alpha = .4, fill = "lightblue") +
      geom_vline(
          data = score_stats,
          aes(xintercept = value, linetype = linetype),
          linewidth = 1,
          col = "lightblue3"
      ) +
      scale_linetype_manual(
          name = "Stat.",
          breaks = c("Mean", "+/- SD"),
          values = c("solid", "dashed")
      ) +
      xlab("Density") +
      ylab("Adjusted Score") +
      theme_minimal() +
      labs(caption = paste(
          "Median: ",
          signif(median(sp$adjustedS), 2),
          "\n",
          "Interquartile Range: ",
          signif(IQR(sp$adjustedS), 3),
          sep = ""
      )) + 
      facet_wrap(~component)

  return(p)

}


#' Plots a plot displaying the observed regimen length distribution for a given regimen, or two given regimens
#' processed output
#' @param pa Patients alignments dataframe created by processAlignments
#' @param components A set of regimens of interest
#' @param top_n Top n most frequent regimens to plot. Ignored if components provided. Default is 6
#' @return plot - A ggplot object
#' @export
#' @importFrom ggplot2 ggplot aes geom_histogram geom_density geom_vline scale_linetype_manual theme_minimal labs xlab ylab facet_wrap
plotRegimenLengthDistribution <- function(pa, components = NULL, top_n = 6) {
  # If component column does not exist, create it from regName
  if(!"component" %in% names(pa) & "regName" %in% names(pa)){
    pa$component <- pa$regName
  }

  if (is.null(components) | !any(components %in% pa$component)) {
      # take most prevelant   
      top_components <- table(pa$component) %>% 
          sort() %>% 
          tail(n = top_n) %>% 
          names()
  } else {
      top_components <- components
  }

  sc <- pa %>% 
      filter(component %in% top_components)


  score_stats <- sc %>% 
      group_by(component) %>% 
      reframe(statistic = c("mean","sd_upper","sd_lower"),
                linetype = c("Mean","+/- SD","+/- SD"),
                value = c(mean(regLength),
                          mean(regLength) + sd(regLength),
                          mean(regLength) - sd(regLength)
                          )
                )

  p <- ggplot(sc, aes(x = regLength)) +
      geom_histogram(binwidth = 5,
                    color = "darkblue",
                    fill = "grey80") +
      geom_density(alpha = .4, fill = "lightblue") +
      geom_vline(
          data = score_stats,
          aes(xintercept = value, linetype = linetype),
          linewidth = 1,
          col = "lightblue3"
      ) +
      scale_linetype_manual(
          name = "Stat.",
          breaks = c("Mean", "+/- SD"),
          values = c("solid", "dashed")
      ) +
      xlab("Density") +
      ylab("Regimen Length") +
      theme_minimal() +
      labs(caption = paste(
          "Median: ",
          signif(median(sc$regLength), 2),
          "\n",
          "Interquartile Range: ",
          signif(IQR(sc$regLength), 3),
          sep = ""
      )) +
      facet_wrap(~component)

    return(p)

}


#' Plot frequency of the top N most frequent regimens
#' @param pa Patients alignments dataframe created by processAlignments
#' @param top_n Top n most frequent regimens. Default is 10
#' @return plot - A ggplot object
#' @export
#' @importFrom dplyr count mutate slice_head
#' @importFrom ggplot2 ggplot aes geom_histogram geom_density geom_vline scale_linetype_manual theme_minimal labs xlab ylab facet_wrap
plotFrequency <- function(pa, top_n = 10) {
  # If component column does not exist, create it from regName
  if(!"component" %in% names(pa) & "regName" %in% names(pa)){
    pa$component <- pa$regName
  }
  # calculate frequency of each regimen  
  freqPlot = pa %>%
    count(component, sort = T) %>%
    mutate(f = n / sum(n)) %>%
    slice_head(n = top_n) %>% 
    mutate(component = factor(component, levels = rev(component)))

  # prepare colors
  components <- freqPlot$component

  cols <- ggsci::pal_jco()(10)
  cols <- c(cols, ggsci::pal_jama()(7))

  if (top_n < 18) {
    names(cols) <- components[sample(x = c(1:17))]
  } else{
    cols <- rep(cols, top_n)
    names(cols) <- components[sample(x = c(1:top_n))]
  }

  p <- freqPlot %>% 
    ggplot(aes(
      y = component,
      x = f,
      fill = component
    )) +
    geom_bar(stat = "identity") +
    scale_fill_manual(values = cols) +
    theme_minimal() +
    theme(legend.position = "none")

  return(p) 
}


#' Plots a plot displaying the ERA frequency of the top N most frequent eras
#' @param processedEras An output dataframe created by calculateEras
#' @param N The number of top rows to plot
#' @export
#' @importFrom ggplot2 ggplot aes geom_bar theme element_blank element_text ylab xlab ggtitle
#' @importFrom ggplot2 element_line scale_fill_manual scale_color_manual coord_flip
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

  fline <- ggplot(na.omit(firstLine_Tab.p), aes(x = Var1, y = Freq, fill = Var1, col = "black")) +
    geom_bar(stat = "identity") +
    theme(panel.background = element_blank(),
          panel.grid.major = element_line(colour = "grey95"),
          legend.position = "none") +
    scale_fill_manual(values = cols) +
    scale_color_manual(values = c("black" = "black")) +
    ylab("Frequency") + 
    xlab("") + 
    ggtitle("First Regimen") +
    coord_flip() +
    theme(
      axis.text.x = element_text(size = 14),
      axis.text.y = element_text(size = 15))

  sline <- ggplot(na.omit(secondLine_Tab.p), aes(x = Var1, y = Freq, fill = Var1, col = "black")) +
    geom_bar(stat = "identity") +
    theme(panel.background = element_blank(),
          panel.grid.major = element_line(colour = "grey95"),
          legend.position = "none") +
    scale_fill_manual(values = cols) +
    scale_color_manual(values = c("black" = "black")) +
    ylab("Frequency") + 
    xlab("") + 
    ggtitle("Second Regimen") +
    coord_flip() +
    theme(
      axis.text.x = element_text(size = 14),
      axis.text.y = element_text(size = 15))

  gridExtra::grid.arrange(fline, sline, ncol = 2)
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

  sankey_first <- firstLine[ ,c("personID","component")]
  sankey_sec <- secondLine[ ,c("personID","component")]
  sankey_third <- thirdLine[ ,c("personID","component")]

  colnames(sankey_first) <- c("personID","Var1")
  colnames(sankey_sec) <- c("personID","Var1")
  colnames(sankey_third) <- c("personID","Var1")

  colnames(regGroups) <- c("Var1","regGroup")

  sankey_first <- merge(sankey_first, regGroups, by="Var1")[,c(2,3)]
  sankey_sec <- merge(sankey_sec, regGroups, by="Var1")[,c(2,3)]
  sankey_third <- merge(sankey_third, regGroups, by="Var1")[,c(2,3)]

  colnames(sankey_first) <- c("personID","First Line")
  colnames(sankey_sec) <- c("personID","Second Line")
  colnames(sankey_third) <- c("personID","Subsequent Lines")

  sankey_all <- merge(merge(sankey_first, sankey_sec, all = T), sankey_third, all=T)
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

  tt1 <- tt1[!tt1$First.Line == tt1$Second.Line,]
  tt2 <- tt2[!tt2$Second.Line == tt2$Subsequent.Lines,]

  tt1$First.Line <- paste(tt1$First.Line, "(1st)", sep = " ")
  tt1$Second.Line <- paste(tt1$Second.Line, "(2nd)", sep = " ")

  tt2$Second.Line <- paste(tt2$Second.Line, "(2nd)", sep = " ")
  tt2$Subsequent.Lines <- paste(tt2$Subsequent.Lines, "(3rd)", sep = " ")

  colnames(tt1) <- c("source", "target", "value")
  colnames(tt2) <- c("source", "target", "value")

  links <- rbind(tt1, tt2)

  links <- links[!links$target %in% c(" (2nd)"," (3rd)"),]
  links <- links[!links$source %in% c(" (2nd)"," (3rd)"),]

  nodes <- data.frame(
    name=c(as.character(links$source),
           as.character(links$target)) %>% unique()
  )

  links$IDsource <- match(links$source, nodes$name) - 1
  links$IDtarget <- match(links$target, nodes$name) - 1

  p <- networkD3::sankeyNetwork(Links = links, Nodes = nodes,
                     Source = "IDsource", Target = "IDtarget",
                     Value = "value", NodeID = "name",
                     sinksRight=FALSE, width = 2200, height = 1000,
                     fontSize = 28, fontFamily = "calibri")

  networkFile <- paste(saveLocation, "/", fileName, ".html", sep="")

  networkD3::saveNetwork(p, file = networkFile)

  webshot::webshot(url = networkFile, file = paste(saveLocation,"/",fileName,".png",sep=""), vwidth = 2200, vheight = 1000)


  }
