# prepare libraries and load
#if (!requireNamespace("BiocManager", quietly = TRUE))
#    install.packages("BiocManager")
#BiocManager::install("DESeq2")
library(DESeq2)

#docker run -v /rti-01/eearley/vidus:/vidus/ -i -t rtibiocloud/deseq2:1.22.2
setwd("vidus")

# load sample phenotype and technical data
options(stringsAsFactors = F)
bio.vars <- read.delim("./vidus_hiv_acquisition_phenotype_variables.txt",
    header = T, sep = "\t")
art.vars <- read.csv("./vidus_art_phenotype_data.csv", 
    header = T)
tech.vars <- read.delim("./vidus_rna_seq_technical_variables.txt", 
    header = T, sep = "\t")
geno.pcs <- read.table("./vidus_hiv_acquisition_all_samples_top10_genotype_pcs.txt",
    header = T)
#cell type proportions using full LM22 dataset (22 cell types)
ctp<-read.table("./hiv_status_candidate_gene_dge_cell_type_proportions_lm22.txt",
    header = T,sep = "\t")
#cell type proportions using a subset of LM22 (just 10 cell types)
#ctp.subset<-read.table("/shared/vidus/hiv_status_candidate_gene_dge_cell_type_proportions_lm22_subset.txt",header=T,sep="\t")
#art.vars<-read.csv("/shared/vidus/VIDUS_concurrent_ART_v2.csv",header=T)
drug.vars<-read.csv("./VIDUS_RNAseq_drug_use_l6m.csv",header=T)
samples<-read.table("./vidus_sample_list.txt",header=F)



# Rename sample IDs for pheno data
regex.match <- regexpr(text = bio.vars$iid, pattern = "93-\\d\\d\\d\\d", perl = T)
new.ids <- regmatches(x = bio.vars$iid, m = regex.match)
if(length(new.ids) != length(bio.vars$iid)){ stop("ID renaming failed.") }
bio.vars$iid <- new.ids

# Add RNA-seq variables to initial phenotype table
pheno.tmp <- merge(x = bio.vars, y = tech.vars, by.x = "iid", by.y = "SUBCODE")
# Add genotype PCs
pheno.tmp <- merge(x = pheno.tmp, y = geno.pcs, by.x = "iid", by.y = "IID")

# Rename sample IDs for ART data
regex.match <- regexpr(text = art.vars$iid, pattern = "93-\\d\\d\\d\\d", perl = T)
new.ids <- regmatches(x = art.vars$iid, m = regex.match)
if(length(new.ids) != length(art.vars$iid)){ stop("ID renaming failed.") }
art.vars$iid <- new.ids

# Subset ART data
art.vars <- subset(x = art.vars, 
    subset = iid %in% intersect(art.vars$iid, pheno.tmp$iid), 
    select = c("iid", "vl", "viralsuppressed"))

# Add ART data to pheno data
master.pheno <- pheno.tmp
master.pheno$proximal_log10_vl <- 1
master.pheno$viral_suppressed <- 1
if(any(! art.vars$iid %in% master.pheno$iid)){
    stop("Incomplete ID matching")
}
master.pheno$proximal_log10_vl[match(x = art.vars$iid, table = master.pheno$iid)] <- art.vars$vl
master.pheno$viral_suppressed[match(x = art.vars$iid, table = master.pheno$iid)] <- art.vars$viralsuppressed
master.pheno$viral_suppressed <- as.factor(master.pheno$viral_suppressed)

# Verify that HIV controls have "0" values for viral laod
if(any(master.pheno[master.pheno$hiv == 0, "proximal_log10_vl"] > 1)){
    stop("Control sample with >1 log10(VL) value")
}

# add cell type proportions
rownames(ctp) <- ctp$Mixture
cell.types <- c('B.cells.naive', 'B.cells.memory', 'Plasma.cells', 'T.cells.CD8', 
    'T.cells.CD4.naive', 'T.cells.CD4.memory.resting', 
    'T.cells.CD4.memory.activated', 'T.cells.follicular.helper', 
    'T.cells.regulatory..Tregs.', 'T.cells.gamma.delta', 'NK.cells.resting', 
    'NK.cells.activated', 'Monocytes', 'Macrophages.M0', 'Macrophages.M1', 
    'Macrophages.M2', 'Dendritic.cells.resting', 'Dendritic.cells.activated', 
    'Mast.cells.resting', 'Mast.cells.activated', 'Eosinophils', 'Neutrophils')

ctp.scores <- ctp$Absolute.score..sig.score.
ctp <- ctp[,cell.types]

# Convert cell type proportion data to relative proportions
rel.ctp<-ctp
rel.ctp <- t(sapply(1:length(ctp.scores),
    function(i){
        as.numeric(ctp[i,]/ctp.scores[i])
    }))
rownames(rel.ctp) <- rownames(ctp)
colnames(rel.ctp) <- colnames(ctp)
dim(rel.ctp)
rel.ctp<-as.data.frame(rel.ctp)
rel.ctp$iid<-rownames(rel.ctp)
rel.ctp$cd4Tcells.rel <- apply(rel.ctp[,c("T.cells.CD4.naive", "T.cells.CD4.memory.resting", "T.cells.CD4.memory.activated")], 1, sum)
rel.ctp$Bcells.rel <- apply(rel.ctp[,c("B.cells.naive","B.cells.memory")],1,sum)
rel.ctp$granulocytes.rel <- apply(rel.ctp[,c("Mast.cells.resting","Mast.cells.activated","Eosinophils","Neutrophils")],1,sum)
rel.ctp$T.cells.CD8.rel <- rel.ctp$T.cells.CD8
rel.ctp$Monocytes.rel <- rel.ctp$Monocytes


# collapsing 22 cell types into 5 relevant groups:
# CD4+ Tcells, CD8+ Tcells, B cells, Monocytes, ganulocytes
ctp$cd4Tcells <- apply(ctp[,c("T.cells.CD4.naive", "T.cells.CD4.memory.resting", "T.cells.CD4.memory.activated")], 1, sum)
ctp$Bcells <- apply(ctp[,c("B.cells.naive","B.cells.memory")],1,sum)
ctp$granulocytes <- apply(ctp[,c("Mast.cells.resting","Mast.cells.activated","Eosinophils","Neutrophils")],1,sum)



# merge with master.pheno
ctp$iid<-rownames(ctp)
master.pheno<-merge(master.pheno, ctp[,c("cd4Tcells","Bcells","granulocytes","Monocytes","T.cells.CD8","iid")], by="iid", all.x=T)
master.pheno<-merge(master.pheno, rel.ctp[c("cd4Tcells.rel","Bcells.rel","granulocytes.rel","T.cells.CD8.rel","Monocytes.rel","iid")], by="iid",all.x=T)




# add drug use
master.pheno<-merge(master.pheno,drug.vars,by="gwas_code",all.x=T)
master.pheno<-master.pheno[!names(master.pheno) %in% c("hiv.y","female.y","marij_noninj_l6m.y","ageatint.y")]
colnames(master.pheno)[c(3,5,6,7)]<-c("female","hiv","marij_noninj_l6m","ageatint")

#00 = hiv- cocaine-
#01 = hiv- cocaine+
#10 = hiv+ cocaine-
#11 = hiv+ cocaine+
master.pheno$group <- factor(paste0(master.pheno$hiv,master.pheno$cocaine_l6m))

# ageatint should not be an integer unless we expect expression to scale linearly over time
# instead, M. Love suggests binning into 3-5 groups and factorizing
master.pheno$age.bin = cut(master.pheno$ageatint,breaks=5)




factor.vars <- c("hiv", "female", "std_ever","Container_Inventory_Code", 
    "Library.Plate.ID", "FlowCell.Lot.", "Seq.Date", 
    "Extraction.Kit.Lot.Number",
    "benzo_noninj_l6m","heroin_l6m","prescript_l6m","opioid_l6m","cocaine_l6m","crack_l6m","anycoc_l6m","meth_l6m","stim_l6m","anydrug_l6m", "group")
for(factor.var in factor.vars){
    print(paste0("Converting ", factor.var, " to factor"))
    master.pheno[, factor.var] <- as.factor(master.pheno[, factor.var])
}

cat("\nPhenotype table dimensions: ", dim(master.pheno), "\n")



# Load GTF file and make gene coordinate map
options(stringsAsFactors = F)
if(! file.exists("./gencode.v28.annotation.gtf.gz")){
    download.file("ftp://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_28/gencode.v28.annotation.gtf.gz", 
        destfile = "./gencode.v28.annotation.gtf.gz")
}
gtf <- read.delim("./gencode.v28.annotation.gtf.gz", 
    comment.char = "#", sep = "\t", header = F)

# Load or create ID to gene name map
if(file.exists("./gencode_v28_gene_id_name_map.rds")){
    id.name.map = readRDS("./gencode_v28_gene_id_name_map.rds")
}else{
    print("Creating .rds gene map file")
    anno.data <- strsplit(gtf[grep(gtf[,9], pattern = "gene_name"),9], split = ";")
    id.name.map <- lapply(1:length(anno.data), function(x){
        id <- tail(strsplit(anno.data[[x]][grep(anno.data[[x]], pattern = "gene_id")], split = " ")[[1]], n = 1)
        name <- tail(strsplit(anno.data[[x]][grep(anno.data[[x]], pattern = "gene_name")], split = " ")[[1]], n = 1)
        return(c(id,name))
    })
    id.name.map <- do.call(rbind, unique(id.name.map))
    colnames(id.name.map) <- c("GENEID", "GENENAME")
    saveRDS(id.name.map, "./gencode_v28_gene_id_name_map.rds")
}



#########################
# LOAD EXPRESSION DATA #
##########################

# Transcript expression data
vidus.tx.data<- readRDS("./vidus_salmon_dte_tx_data_gencode28.rds")
vidus.tx.data$abundance <- vidus.tx.data$abundance[,master.pheno$iid]
vidus.tx.data$counts <- vidus.tx.data$counts[,master.pheno$iid]
vidus.tx.data$length <- vidus.tx.data$length[,master.pheno$iid]
lapply(vidus.tx.data, dim)
# Create initial model formula (will be updated later)
model.vars <- c('hiv', 'female', 'age.bin', 'RNA_Quality_Score',
    'PC1', 'PC2', 'PC3', 'PC4', 'PC5')
initial.model <- as.formula(paste0("~", paste0(model.vars, collapse = " + ")))
# create tx-level data objects
vidus.tx.dds <- DESeqDataSetFromTximport(txi = vidus.tx.data, 
    design = initial.model, colData = master.pheno)
dim(vidus.tx.dds)


# VL only
pheno.vl = master.pheno[master.pheno$hiv == 0,]
pheno.vl = rbind(pheno.vl, 
                 master.pheno[master.pheno$hiv == 1 & master.pheno$viral_suppressed == 0,])
dim(pheno.vl)
vidus.vl.tx.data = vidus.tx.data
vidus.vl.tx.data$abundance = vidus.vl.tx.data$abundance[,pheno.vl$iid]
vidus.vl.tx.data$counts = vidus.vl.tx.data$counts[,pheno.vl$iid]
vidus.vl.tx.data$length = vidus.vl.tx.data$length[,pheno.vl$iid]
lapply(vidus.vl.tx.data, dim)
model.vars <- c("female","age.bin","RNA_Quality_Score",
    "PC1","PC2","PC3","PC4","PC5")
initial.model <- as.formula(paste0("~", paste0(model.vars, collapse = " + ")))
vidus.vl.tx.dds <- DESeqDataSetFromTximport(txi = vidus.vl.tx.data,
    design = initial.model, colData = pheno.vl)


# no VL only
pheno.novl = master.pheno[master.pheno$hiv == 0,]
pheno.novl = rbind(pheno.novl, 
                 master.pheno[master.pheno$hiv == 1 & master.pheno$viral_suppressed == 1,])
dim(pheno.novl)
vidus.novl.tx.data = vidus.tx.data
vidus.novl.tx.data$abundance = vidus.novl.tx.data$abundance[,pheno.novl$iid]
vidus.novl.tx.data$counts = vidus.novl.tx.data$counts[,pheno.novl$iid]
vidus.novl.tx.data$length = vidus.novl.tx.data$length[,pheno.novl$iid]
lapply(vidus.novl.tx.data, dim)
model.vars <- c("female","age.bin","RNA_Quality_Score",
    "PC1","PC2","PC3","PC4","PC5")
initial.model <- as.formula(paste0("~", paste0(model.vars, collapse = " + ")))
vidus.novl.tx.dds <- DESeqDataSetFromTximport(txi = vidus.novl.tx.data,
    design = initial.model, colData = pheno.novl)


# cocaine only
pheno.coc<-master.pheno[master.pheno$anycoc_l6m == 1,]
dim(pheno.coc)
vidus.coc.tx.data = vidus.tx.data
vidus.coc.tx.data$abundance = vidus.coc.tx.data$abundance[,pheno.coc$iid]
vidus.coc.tx.data$counts = vidus.coc.tx.data$counts[,pheno.coc$iid]
vidus.coc.tx.data$length = vidus.coc.tx.data$length[,pheno.coc$iid]
lapply(vidus.coc.tx.data, dim)
model.vars <- c("female","age.bin","RNA_Quality_Score",
    "PC1","PC2","PC3","PC4","PC5")
initial.model <- as.formula(paste0("~", paste0(model.vars, collapse = " + ")))
vidus.coc.tx.dds <- DESeqDataSetFromTximport(txi = vidus.coc.tx.data,
    design = initial.model, colData = pheno.coc)


# no cocaine only
pheno.noncoc<-master.pheno[master.pheno$anycoc_l6m == 0,]
dim(pheno.noncoc)
vidus.noncoc.tx.data = vidus.tx.data
vidus.noncoc.tx.data$abundance = vidus.noncoc.tx.data$abundance[,pheno.noncoc$iid]
vidus.noncoc.tx.data$counts = vidus.noncoc.tx.data$counts[,pheno.noncoc$iid]
vidus.noncoc.tx.data$length = vidus.noncoc.tx.data$length[,pheno.noncoc$iid]
lapply(vidus.noncoc.tx.data, dim)
model.vars <- c("female","age.bin","RNA_Quality_Score",
    "PC1","PC2","PC3","PC4","PC5")
initial.model <- as.formula(paste0("~", paste0(model.vars, collapse = " + ")))
vidus.noncoc.tx.dds <- DESeqDataSetFromTximport(txi = vidus.noncoc.tx.data,
    design = initial.model, colData = pheno.noncoc)


####################################
# FILTER OUT LOWLY EXPRESSED GENES #
####################################

# filter out lowly expressed genes
count.filter <- function(dds, sample.cutoff = 0.1, count.cutoff = 10, force.keep = c()){
    count.matrix <- counts(dds)
    force.keep.indices <- which(rownames(count.matrix) %in% force.keep)
    if(length(force.keep.indices) != length(force.keep)){
        warning("Not all force kept genes found.")
    }
    # Calculate sample fraction that exceeds count cutoff
    passed.count.cutoff <- rowMeans(count.matrix > count.cutoff, na.rm = F)
    keep.indices <- which(passed.count.cutoff > sample.cutoff)
    keep.indices <- unique(c(keep.indices, force.keep.indices))
    dds[keep.indices,]
}

# Round a decimal at the hundredths place to either a 0 or 5
sample.cutoff.calc <- function(min.fraction){
    min.percent <- floor(min.fraction*100)
    if(min.percent %% 10 >= 5){
        (floor(min.percent / 10) * 10 + 5) / 100
    }else{
        floor(min.fraction * 10) / 10
    }
}





# Full cohort, N=588
# Get approximate data set fraction for the smaller of cases and controls
min.fraction <- min(table(master.pheno$hiv))/sum(table(master.pheno$hiv, useNA = "always"))
sample.threshold <- sample.cutoff.calc(min.fraction)
filtered.vidus.tx.dds <- count.filter(vidus.tx.dds, count.cutoff = 10,
    sample.cutoff = sample.threshold, force.keep = c())
dim(filtered.vidus.tx.dds) #
filtered.vidus.tx.dds <- estimateSizeFactors(filtered.vidus.tx.dds)
save(filtered.vidus.tx.dds, file="VIDUS_HIV_DTE_deseq2_2023_11_28.RData")


# VL only
min.fraction <- min(table(pheno.vl$hiv))/sum(table(pheno.vl$hiv, useNA = "always"))
sample.threshold <- sample.cutoff.calc(min.fraction)
filtered.vidus.vl.tx.dds <- count.filter(vidus.vl.tx.dds, count.cutoff = 10,
    sample.cutoff = sample.threshold, force.keep = c())
dim(filtered.vidus.vl.tx.dds) 
filtered.vidus.vl.tx.dds <- estimateSizeFactors(filtered.vidus.vl.tx.dds)
save(filtered.vidus.vl.tx.dds, file="VIDUS_HIV_DTE_vl_deseq2_2023_11_28.RData")

# no VL only
min.fraction <- min(table(pheno.novl$hiv))/sum(table(pheno.novl$hiv, useNA = "always"))
sample.threshold <- sample.cutoff.calc(min.fraction)
filtered.vidus.novl.tx.dds <- count.filter(vidus.novl.tx.dds, count.cutoff = 10,
    sample.cutoff = sample.threshold, force.keep = c())
dim(filtered.vidus.novl.tx.dds) 
filtered.vidus.novl.tx.dds <- estimateSizeFactors(filtered.vidus.novl.tx.dds)
save(filtered.vidus.novl.tx.dds, file="VIDUS_HIV_DTE_novl_deseq2_2023_11_28.RData")



# cocaine only
min.fraction <- min(table(pheno.coc$hiv))/sum(table(pheno.coc$hiv, useNA = "always"))
sample.threshold <- sample.cutoff.calc(min.fraction)
filtered.vidus.coc.tx.dds <- count.filter(vidus.coc.tx.dds, count.cutoff = 10, 
    sample.cutoff = sample.threshold, force.keep = c())
dim(filtered.vidus.coc.tx.dds) 
filtered.vidus.coc.tx.dds <- estimateSizeFactors(filtered.vidus.coc.tx.dds)
save(filtered.vidus.coc.tx.dds, file="VIDUS_HIV_DTE_coc_deseq2_2023_11_28.RData")




# no cocaine only
min.fraction <- min(table(pheno.noncoc$hiv))/sum(table(pheno.noncoc$hiv, useNA = "always"))
sample.threshold <- sample.cutoff.calc(min.fraction)
filtered.vidus.noncoc.tx.dds <- count.filter(vidus.noncoc.tx.dds, count.cutoff = 10, 
    sample.cutoff = sample.threshold, force.keep = c())
dim(filtered.vidus.noncoc.tx.dds) 
filtered.vidus.noncoc.tx.dds <- estimateSizeFactors(filtered.vidus.noncoc.tx.dds)
save(filtered.vidus.noncoc.tx.dds, file="VIDUS_HIV_DTE_noncoc_deseq2_2023_11_28.RData")




#### save images for model fitting ####
#save.image("VIDUS_HIV_DTE_deseq2_2023_11_28.RData")


