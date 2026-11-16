// Author: Naveen Duhan
// Automated post-BLAST contig triage and multi-evidence novel virus discovery subworkflows

include { viral_hmm } from '../modules/viral_hmm.nf'
include { viral_protein_search } from '../modules/viral_protein_search.nf'
include { foldseek_viral } from '../modules/foldseek_viral.nf'
include { novel_phylogeny } from '../modules/novel_phylogeny.nf'

process TRIAGE_CONTIGS {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/novel_virus_detection/details",
        mode: params.publish_mode,
        overwrite: true,
        failOnError: true

    input:
        tuple val(id), path(contigs_fasta), path(blast_hsps)

    output:
        tuple val(id), path("${id}_candidate_contigs.fa"), emit: candidate_contigs
        tuple val(id), path("${id}_triage_manifest.tsv"), emit: manifest
        tuple val(id), path("${id}_triage_summary.txt"), emit: summary

    script:
    def allFlag = params.discovery_all_contigs ? '--include_all_contigs' : ''
    def blastArg = blast_hsps ? "--blast_hsps ${blast_hsps}" : ''
    """
    python3 ${workflow.projectDir}/nextflow/bin/triage_contigs.py \
        --fasta_file ${contigs_fasta} \
        ${blastArg} \
        --prefix ${id} \
        --min_candidate_length ${params.novel_min_contig_length} \
        --known_virus_identity ${params.known_virus_identity} \
        --known_virus_coverage ${params.known_virus_coverage} \
        ${allFlag}
    """
}

process SCAN_VIRAL_ARCHITECTURE {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/novel_virus_detection/details",
        mode: params.publish_mode,
        overwrite: true,
        failOnError: true

    input:
        tuple val(id), path(candidate_contigs)

    output:
        tuple val(id), path("${id}_architecture_metrics.tsv"), emit: architecture
        tuple val(id), path("${id}_candidate_orfs.faa"), emit: orfs

    script:
    """
    python3 ${workflow.projectDir}/nextflow/bin/scan_viral_architecture.py \
        --fasta_file ${candidate_contigs} \
        --prefix ${id} \
        --min_orf_aa ${params.novel_min_orf_aa}
    """
}

process SYNTHESIZE_NOVEL_VIRUSES {
    tag "$id"
    label 'low'

    publishDir "${params.outdir}/novel_virus_detection",
        mode: params.publish_mode,
        overwrite: true,
        failOnError: true

    input:
        tuple val(id), path(contigs_fasta), path(triage_manifest), val(evidence_keys), path(evidence_files)

    output:
        tuple val(id), path("${id}_novel_virus_candidates.xlsx"), emit: candidates_xlsx
        tuple val(id), path("${id}_novel_virus_candidates.tsv"), emit: candidates_tsv
        tuple val(id), path("${id}_novel_virus_candidates.fasta"), emit: candidates_fasta
        tuple val(id), path("${id}_novel_virus_orfs.faa"), emit: candidates_orfs
        tuple val(id), path("${id}_novel_discovery_summary.txt"), emit: summary

    script:
    def fileList = evidence_files instanceof List ? evidence_files : [evidence_files]
    def keyList = evidence_keys instanceof List ? evidence_keys : [evidence_keys]
    def evMap = [keyList, fileList].transpose().collectEntries { key, fileObj -> [(key): fileObj.getName()] }
    def flagPairs = [
        ['coverage', '--coverage'],
        ['virfinder', '--virfinder'],
        ['checkv', '--checkv'],
        ['genomad_virus', '--genomad_virus'],
        ['genomad_plasmid', '--genomad_plasmid'],
        ['hmm', '--hmm_hits'],
        ['vp', '--viral_protein_hits'],
        ['foldseek', '--foldseek_hits']
    ]
    def optionalArgs = flagPairs
        .findAll { pair -> evMap.containsKey(pair[0]) }
        .collect { pair -> "${pair[1]} '${evMap[pair[0]]}'" }
        .join(' ')
    """
    python3 ${workflow.projectDir}/nextflow/bin/synthesize_novel_viruses.py \
        --contigs_fasta '${contigs_fasta}' \
        --candidate_orfs '${evMap['orfs']}' \
        --triage_manifest '${triage_manifest}' \
        --architecture '${evMap['arch']}' \
        --prefix '${id}' \
        ${optionalArgs}
    """
}

workflow CONTIG_TRIAGE {
    take:
        contigs_ch
        blast_hsps_ch

    main:
        if (!params.skip_blast_annotation) {
            ch_triage_in = contigs_ch.join(blast_hsps_ch)
        } else {
            ch_triage_in = contigs_ch.map { id, fasta -> [id, fasta, []] }
        }
        TRIAGE_CONTIGS(ch_triage_in)

    emit:
        candidate_contigs = TRIAGE_CONTIGS.out.candidate_contigs
        manifest = TRIAGE_CONTIGS.out.manifest
        summary = TRIAGE_CONTIGS.out.summary
}

workflow NOVEL_VIRUS_DETECTION {
    take:
        contigs_ch
        candidate_contigs_ch
        triage_manifest_ch
        coverage_stats_ch
        virfinder_table_ch
        checkv_summary_ch
        genomad_virus_ch
        genomad_plasmid_ch

    main:
        ch_hmm_hits = Channel.empty()
        ch_vp_hits = Channel.empty()
        ch_fs_hits = Channel.empty()
        ch_phylo_out = Channel.empty()

        SCAN_VIRAL_ARCHITECTURE(candidate_contigs_ch)

        if (params.run_viral_hmm) {
            viral_hmm(SCAN_VIRAL_ARCHITECTURE.out.orfs)
            ch_hmm_hits = viral_hmm.out.hmm_hits
        }
        if (params.run_viral_protein_blast) {
            viral_protein_search(SCAN_VIRAL_ARCHITECTURE.out.orfs)
            ch_vp_hits = viral_protein_search.out.vp_hits
        }
        if (params.run_foldseek) {
            foldseek_viral(SCAN_VIRAL_ARCHITECTURE.out.orfs)
            ch_fs_hits = foldseek_viral.out.foldseek_hits
        }

        ch_evidence = SCAN_VIRAL_ARCHITECTURE.out.architecture
            .map { id, path -> [id, 'arch', path] }
            .mix(
                SCAN_VIRAL_ARCHITECTURE.out.orfs.map { id, path -> [id, 'orfs', path] },
                coverage_stats_ch.map { id, path -> [id, 'coverage', path] },
                virfinder_table_ch.map { id, path -> [id, 'virfinder', path] },
                checkv_summary_ch.map { id, path -> [id, 'checkv', path] },
                genomad_virus_ch.map { id, path -> [id, 'genomad_virus', path] },
                genomad_plasmid_ch.map { id, path -> [id, 'genomad_plasmid', path] },
                ch_hmm_hits.map { id, path -> [id, 'hmm', path] },
                ch_vp_hits.map { id, path -> [id, 'vp', path] },
                ch_fs_hits.map { id, path -> [id, 'foldseek', path] }
            )
            .groupTuple()

        ch_synth_in = contigs_ch
            .join(triage_manifest_ch)
            .join(ch_evidence)

        SYNTHESIZE_NOVEL_VIRUSES(ch_synth_in)

        if (params.run_novel_phylogeny) {
            novel_phylogeny(SYNTHESIZE_NOVEL_VIRUSES.out.candidates_orfs)
            ch_phylo_out = novel_phylogeny.out.phylo_outputs
        }

    emit:
        candidates_xlsx = SYNTHESIZE_NOVEL_VIRUSES.out.candidates_xlsx
        candidates_tsv = SYNTHESIZE_NOVEL_VIRUSES.out.candidates_tsv
        candidates_fasta = SYNTHESIZE_NOVEL_VIRUSES.out.candidates_fasta
        candidates_orfs = SYNTHESIZE_NOVEL_VIRUSES.out.candidates_orfs
        summary = SYNTHESIZE_NOVEL_VIRUSES.out.summary
        phylogeny = ch_phylo_out
}
