# -------------------------------------------------------------------------- #
options = commandArgs(trailingOnly=TRUE)
source(file.path(options[2],'/Argument_Parser.R'))
argv = Parse_Arguments('Extract_Read_Statistics')


# ------------------------------------------------------------------------ #
# for STAR
MappingStats_STAR = function(path, name){

    require(stringr)
    require(data.table)
    s = scan(path, what='character', sep='\n', quiet=TRUE)
    s = as.numeric(str_replace(s[c(5,8,23,25)],'^.+\\t',''))
    d = data.table(sample = name,
                   mapped = c('reads.total','map.uniq','map.mult','map.disc','map.total'),
                   cnts   = c(s,s[2]+s[3]))

    d[,freq := round(cnts/cnts[1],3)]
    d$type = 'mapped'
    return(d)
}

# -------------------------------------------------------------------------- #
Extract_Read_Statistics = function(
    bamfile           = NULL,
    outfile           = NULL,
    sample            = 'Sample',
    star_output_types = 'Gene',
    mito_chr          = 'chrM'

){
    if(is.null(bamfile))
        stop('bamfile not specified')

    if(is.null(outfile))
        stop('outfile not specified')

    suppressPackageStartupMessages({
      library(Rsamtools)
      library(data.table)
    })

    basedir = dirname(bamfile)

    star_output_types = unlist(strsplit(star_output_types,' '))

    message('STAR Mapping Statistics ...')
    stat_file     = file.path(basedir, paste(sample, 'Log.final.out', sep='_'))
    stats_mapping = MappingStats_STAR(stat_file, sample)

    message('% Mapping to mitochondrial genome ...')
    targets = scanBamHeader(bamfile)[[1]]$targets
    mito_count = NA
    if(mito_chr %in% names(targets)){
        mito_count = idxstatsBam(bamfile)
        mito_count = subset(mito_count, seqnames == mito_chr)$mapped
    }
    stats_mito = data.frame(
        sample = sample,
        mapped = 'mito_count',
        cnts   = mito_count,
        freq   = NA,
        type   = 'mito'
    )

    message('Feature UMI statistics ...')
    solo_stats_list = list()
    for(star_output_type in star_output_types){
        solo_path       = file.path(basedir, paste(sample,'Solo.out', sep='_'))
        solo_stat_path  = file.path(solo_path, star_output_type, 'Features.stats')
        if(!file.exists(solo_stat_path))
            error(paste('File does not exist:', solo_stat_path))

        solo_stat_table = cbind(
            sample = sample, read.table(solo_stat_path, header = FALSE)
        )
        setnames(solo_stat_table,2:3, c('mapped','cnts'))
        solo_stat_table$freq = NA
        solo_stat_table$type = star_output_type
        solo_stats_list[[star_output_type]] = solo_stat_table
    }
    solo_stats_combined = rbindlist(solo_stats_list)

    message('Writing read statistics ...')
    read_statistics = rbindlist(list(
        stats_mapping,
        stats_mito,
        solo_stats_combined
    ))
    read_statistics$freq = round(read_statistics$cnts / subset(read_statistics, mapped == 'reads.total')$cnts,2)

    write.table(read_statistics, outfile,
        row.names=TRUE, col.names=TRUE,
        sep='\t',quote=FALSE)
}

# -------------------------------------------------------------------------- #
Extract_Read_Statistics(
      bamfile           = argv$input[['bamfile']],
      outfile           = argv$output[['outfile']],
      sample            = argv$params[['sample']],
      star_output_types = argv$params[['star_output_types']],
      mito_chr          = argv$params[['mito_chr']]
  )
