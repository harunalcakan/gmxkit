# GmxKit — English UI strings (I18N_*)

I18N_app_subtitle='GROMACS protein–ligand MD'
I18N_first_install='First-time setup?  →  ./md install   (pip; install GROMACS yourself)'

# Stage labels
I18N_stage_00='Environment check'
I18N_stage_00b='Metalloenzyme PDB (HSD, Zn)'
I18N_stage_01='Protein topology (pdb2gmx)'
I18N_stage_02='Ligand (CGenFF + itp)'
I18N_stage_03='Complex assembly'
I18N_stage_04='Solvation + ions (+ em.tpr)'
I18N_stage_05='Index + ligand posre'
I18N_stage_06_local='MD scripts (run_local_md.sh)'
I18N_stage_06_truba='TRUBA Slurm package'

# Status board
I18N_hdr_id='ID'
I18N_hdr_stage='STAGE'
I18N_hdr_status='STATUS'
I18N_status_waiting='pending'
I18N_status_done='done'
I18N_prep_label='  Prep      '
I18N_sim_label='  Simulation'
I18N_queue_label='  Queue     '
I18N_queue_empty='(no jobs yet)'
I18N_prep_progress='%d/%d done'
I18N_prep_next='  →  next: %s'

# Recommendations
I18N_rec_label='Suggestion'
I18N_rec_prep='  →  [1] Prep — stage %s (%s)'
I18N_rec_queue_watch='  →  [1] Queue — watch status / logs'
I18N_rec_queue_em='  →  [1] Queue — submit EM'
I18N_rec_queue_nvt='  →  [1] Queue — submit NVT'
I18N_rec_queue_npt='  →  [1] Queue — submit NPT'
I18N_rec_queue_md='  →  [1] Queue — submit production MD'
I18N_rec_analyze='  →  [6] Analysis — PBC + RMSD/RMSF/Rg/SASA'
I18N_rec_queue_start='  →  [1] Queue — start simulation'

# Main menu (prep complete)
I18N_menu_queue='  1  [J] Queue        background — job ID, watch, cancel'
I18N_menu_sim='  2  [S] Simulation   foreground — asks duration/temperature'
I18N_menu_control='  3  [K] Control      binding + prep audit'
I18N_menu_analyze='  6  [L] Analysis     PBC traj + RMSD/RMSF/Rg/SASA'
I18N_menu_prep='  4  [P] Prep         stages 00–06 (re-run)'
I18N_menu_tools='  5  [A] Tools        cleanup, reset, config'
I18N_menu_exit='  0  [Q] Quit'
I18N_menu_hint_fg='  S=foreground · J=background (long runs)'
I18N_menu_prep_only='  1  [P] Prep         stages 00–06 (recommended)'
I18N_menu_tools_short='  2  [A] Tools        install, cleanup, config'
I18N_menu_hint_locked='  Queue and simulation unlock after prep stage 06.'

I18N_prompt_main_full='Choice (1–6 / J S K L P A Q / r=status): '
I18N_prompt_main_prep='Choice (1–2 / P A Q): '
I18N_prompt_choice='Choice: '
I18N_prompt_stage='Stage ID or option: '
I18N_prompt_force_stage='Force re-run stage (00, 01 …): '
I18N_pause_main='↵ ENTER to return to main menu... '
I18N_exit_msg='Bye.'
I18N_warn_main_full='Enter 1–6, 0, or J/S/K/L/P/A/Q. (r = queue status)'
I18N_warn_main_prep='Enter 1, 2, 0, or P/A/Q.'
I18N_invalid_choice='Invalid choice.'
I18N_invalid_stage='Invalid stage: %s'
I18N_suggest_sim='Simulation → [1] Queue or [2] interactive'

# Prep submenu
I18N_menu_prep_title='  PREP — pick a stage (step by step)   '
I18N_menu_prep_all='  a) Run all stages in order (resume from checkpoint)'
I18N_menu_prep_force='  f) Stage no. + FORCE re-run'
I18N_menu_prep_back='  0) Main menu'

# Simulation submenu
I18N_menu_sim_title='  SIMULATION — foreground (terminal)     '
I18N_menu_sim_nvt='  1) NVT   equilibration'
I18N_menu_sim_npt='  2) NPT   pressure equilibration'
I18N_menu_sim_md='  3) MD    production'
I18N_menu_sim_resume='  4) Resume (MD checkpoint)'
I18N_menu_sim_nvt_y='  5) NVT   (-y, no prompts)'

# Control submenu
I18N_menu_ctrl_title='  CONTROL — binding + audit             '
I18N_menu_ctrl_binding='  1) em binding   2) nvt   3) npt   4) md'
I18N_menu_ctrl_audit='  5) Prep audit'
I18N_menu_ctrl_mdp='  6) Sync MDP (config → nvt/npt/md.mdp)'

# Tools submenu
I18N_menu_tools_title='  TOOLS                                  '
I18N_tool_status='  1) Status table'
I18N_tool_reset='  2) Reset checkpoints (files kept)'
I18N_tool_clean_list='  3) Cleanup: list (dry-run)'
I18N_tool_clean_run='  4) Cleanup: delete outputs (start over)'
I18N_tool_config='  5) Config path + profiles'
I18N_tool_guide='  6) User guide'
I18N_tool_setup='  7) Environment setup'
I18N_tool_setup_opts='  a) setup (conda/venv)  b) setup --system'
I18N_tool_config_path='Config: %s'
I18N_tool_profile_path='Profiles: %s/'
I18N_tool_guide_path='Guide: %s'

# Clean confirm
I18N_clean_opt1='  1) Delete outputs (default backups kept)'
I18N_clean_opt2='  2) + delete mdprep/backups'
I18N_clean_opt3='  3) + delete CGenFF .str'
I18N_clean_cancel='  0) Cancel'

# Common prompts / gates
I18N_confirm_yn='[y/N] '
I18N_confirm_Yn='[Y/n] '
I18N_confirm_gate='Continue? [Y/n/e=edit config/q=cancel] '
I18N_confirm_gate_invalid='Invalid: Y (continue), n/q (cancel), e (edit config)'
I18N_confirm_gate_cancel='Prep step cancelled.'
I18N_confirm_gate_reload='config.sh reloaded — review parameters.'
I18N_confirm_gate_no_tty='PREP_INTERACTIVE: no TTY, confirmation skipped (%s)'
I18N_pause_manual='Press ENTER when ready (Ctrl-C to cancel)... '
I18N_manual_step='>>> MANUAL STEP:'
I18N_dry_run_skip='DRY_RUN: skipped.'
I18N_dry_run_gate='DRY_RUN: gate skipped.'

# Common errors
I18N_err_cmd_missing="Required command not found: '%s' %s"
I18N_err_file_missing="Required file missing: '%s' %s"
I18N_err_dir_missing="Required directory missing: '%s' %s"
I18N_err_unknown_cmd='Unknown: %s. ./md help'
I18N_err_workdir='Cannot cd to WORKDIR: %s'
I18N_err_run_local_md='run_local_md.sh missing — run prep stage 06 first'
I18N_backup_done='Backup: %s -> %s'
I18N_cmd_failed='Command failed (rc=%s): %s  (see: %s)'
I18N_gmx_failed='gmx %s failed (rc=%s). Log: %s'
I18N_gmx_missing_out='gmx %s: expected output missing or empty: %s'
I18N_gmx_done='gmx %s completed.'
I18N_gmx_warn='gmx %s produced warning(s) (see log: %s)'
I18N_checkpoint_done='Checkpoint: %s'
I18N_stage_skip='[%s] already done, skipping (FORCE=1 to re-run).'

# Usage / lang
I18N_usage_title='GmxKit — GROMACS protein–ligand MD toolkit'
I18N_usage_menu='  ./md                         Interactive menu (recommended)'
I18N_usage_same='  ./mdprep/md.sh               Same'
I18N_usage_cli='CLI: check | prep | status | reset | clean | stage NN | nvt | npt | md | binding'
I18N_usage_queue='      queue [submit|chain|status|cancel]  — local job queue (EM/NVT/NPT/MD)'
I18N_usage_analyze='      analyze [all|pbc|rmsd|report]       — PBC traj + RMSD/RMSF/Rg/SASA'
I18N_usage_audit='      audit [--fix-mdp]                   — prep audit (+ MDP sync)'
I18N_usage_install='      install [-y] [--with-apt] [--recreate]  — pip venv (does not install gmx)'
I18N_usage_lang='      lang en|tr                        — UI language (saved in config.sh)'
I18N_usage_workdir='WORKDIR: %s'
I18N_usage_guide='Guide:   %s'
I18N_lang_set='Language set to: %s (saved in config.sh)'
I18N_lang_current='Current language: %s  (en | tr)'
I18N_lang_usage='Usage: ./md lang en|tr'

# run.sh
I18N_run_stage_hdr='######## STAGE: %s ########'
I18N_run_list_stage='STAGE'
I18N_run_list_status='STATUS'
I18N_run_done='completed'
I18N_run_pending='pending'
I18N_run_reset_confirm='Delete all checkpoints? (generated files are NOT removed)'
I18N_run_reset_ok='Checkpoints cleared.'
I18N_run_all_start='Pipeline starting (resume from checkpoint). DRY_RUN=%s'
I18N_run_all_done='All defined stages completed.'
I18N_run_err_script='Stage script missing: %s'
I18N_run_err_stage_arg='Provide stage number/name: ./run.sh stage 02'
I18N_run_err_no_match="No matching stage: '%s'"
I18N_run_err_unknown="Unknown command: '%s'. (check|setup|list|reset|clean|stage|all)"

# install.sh
I18N_install_title='GmxKit — DEPENDENCY INSTALL'
I18N_install_gmx_note='GROMACS is not installed automatically — uses your gmx from the environment'
I18N_install_apt_section='APT (python3, perl — no gmx)'
I18N_install_pip_section='PIP (Python venv — cgenff)'
I18N_install_check_section='ENVIRONMENT CHECK'
I18N_install_report_title='GmxKit install report — %s'
I18N_install_report_script='--- Script install (pip/apt) ---'
I18N_install_report_user='--- You install (script does not) ---'
I18N_install_report_pkg='--- Project package ---'
I18N_install_report_path='Report: %s'
I18N_install_done_banner='  Script dependencies installed →  ./md'
I18N_install_done_gmx='  GROMACS: your installation (config.sh → GMX=)'
I18N_install_done_guide='  Guide: %s'
I18N_install_warn_gmx='gmx not in PATH — install GROMACS; set GMX= in config.sh'
I18N_install_warn_check='Some checks failed (see report)'
I18N_install_confirm_apt='Install python3 + perl via apt? (requires sudo, no gmx) [Y/n] '
I18N_install_unknown='Unknown: %s. ./md install help'

# MDP prompts
I18N_mdp_nvt_hdr='=== NVT: %s ==='
I18N_mdp_npt_hdr='=== NPT: %s ==='
I18N_mdp_md_hdr='=== Production MD: %s ==='
I18N_mdp_current_nvt='Current: %s ps @ %s K (nsteps=%s, dt=%s ps)'
I18N_mdp_current_npt='Current: %s ps @ %s K, ref_p=%s bar (nsteps=%s)'
I18N_mdp_current_md='Current: %s ns @ %s K (nsteps=%s)'
I18N_mdp_prompt_ps='Duration (ps)'
I18N_mdp_prompt_temp='Temperature (K) — ref_t / gen_temp'
I18N_mdp_prompt_temp_short='Temperature (K)'
I18N_mdp_prompt_pressure='Pressure ref_p (bar)'
I18N_mdp_prompt_ns='Duration (ns)'
I18N_mdp_prompt_edit='Open MDP in editor? (e/N): '
I18N_mdp_result_nvt='→ nsteps=%s (%s ps), T=%s K'
I18N_mdp_result_npt='→ nsteps=%s (%s ps), T=%s K, P=%s bar'
I18N_mdp_result_md='→ nsteps=%s (%s ns), T=%s K'

# Queue (bash job_queue.sh)
I18N_queue_title_local='  QUEUE (local workstation)             '
I18N_queue_title_slurm='  QUEUE (Slurm — QUEUE_BACKEND=slurm)    '
I18N_queue_pause='↵ ENTER... '
I18N_queue_continue='Continue?'
I18N_queue_err_python='python3 required (md_queue.py)'
I18N_queue_err_phase='Phase: em | nvt | npt | md'
I18N_queue_err_unknown_phase='Unknown phase: %s'
I18N_queue_err_unknown='Unknown: queue %s. ./md queue help'
I18N_queue_slurm_pack='Generating Slurm package (06_truba_pack)...'
I18N_queue_slurm_no_sbatch='sbatch not found — copy slurm files to cluster and run sbatch there'
I18N_queue_slurm_manual='Manual: sbatch %s'
I18N_queue_slurm_dep='Add dependency afterok:%s?'
I18N_queue_slurm_submit='sbatch %s%s?'
I18N_queue_slurm_chain='Chain: EM → NVT → NPT → MD (Slurm afterok)'
I18N_queue_slurm_chain_confirm='Submit entire chain to queue?'
I18N_queue_slurm_sent='Submitted → Slurm Job ID: %s'
I18N_queue_slurm_chain_done='Chain done. Last job: %s'
I18N_queue_scancel_confirm='scancel %s?'
I18N_queue_scancel_ok='Cancelled: %s'
I18N_queue_slurm_records='=== Slurm records (%s) ==='
I18N_queue_slurm_menu_pack='  1) Generate Slurm package'
I18N_queue_slurm_menu_em='  2) Submit EM   3) NVT   4) NPT   5) MD'
I18N_queue_slurm_menu_chain='  6) Chain (afterok)'
I18N_queue_slurm_menu_status='  7) Status (jobs.tsv + squeue)'
I18N_queue_slurm_menu_cancel='  8) Cancel (scancel)'
I18N_queue_sbatch_yes='yes'
I18N_queue_sbatch_no='no — run sbatch on cluster'
I18N_queue_edit_slurm='Edit slurm file? [e/N] '
I18N_queue_prev_step='  Previous step (%s): Job ID %s'

# Prep confirm gate titles
I18N_gate_pdb2gmx='pdb2gmx — force field and water'
I18N_gate_cgenff='CGenFF — ligand parameters'
I18N_gate_box='Box and solvation'
I18N_gate_genion='genion — add ions'
I18N_gate_em='EM — grompp (mdrun via queue)'
I18N_gate_index='Index and posre — T-coupling groups'

# Gate detail lines (with printf)
I18N_gate_in_pdb='Input PDB     : %s'
I18N_gate_ff='Force field   : %s  (-ff)'
I18N_gate_water='Water model   : %s  (-water)'
I18N_gate_flags='Flags         : ignh=%s missing=%s inter=%s ter=%s'
I18N_gate_out='Output        : %s, %s'
I18N_gate_config_hint='(GROMACS will not prompt; values from config.sh — e to edit)'
I18N_gate_lig_resi='Ligand RESI   : %s  (must match mol2 + .str)'
I18N_gate_stream='Stream file   : %s'
I18N_gate_ff_dir='Force field   : %s'
I18N_gate_outputs='Outputs       : %s, %s, %s'

# cleanup
I18N_clean_confirm1='Delete the files listed above? (inputs are kept)'
I18N_clean_confirm2='Are you sure? This cannot be undone (do you have backups?)'

# CGenFF pause gate (multiline passed as single t call - use heredoc in stage)
I18N_cgenff_pause='CGenFF step:
  1) Upload %s to: %s
  2) RESI name must be %s (same as mol2).
  3) Do NOT select Include parameters already in CGenFF.
  4) Save downloaded .str as %s in WORKDIR.'

# Stage prerequisites
I18N_err_run_check_first='Run environment check first: ./mdprep/run.sh check'
I18N_err_run_protein_first='Run protein stage first: ./mdprep/run.sh stage 01'

# Summary line detection (md.sh)
I18N_summary_running_marker='running'

# Project mode (init / multi-directory)
I18N_usage_init='      init [DIR]                        — new project folder (.gmxkit + templates)'
I18N_usage_project='      -C DIR / --project DIR           — use that data directory'
I18N_init_copied_mdp='Template copied: %s'
I18N_init_ff_link='Force field linked: %s'
I18N_init_ready='Project ready: %s'
I18N_init_next_steps='Next steps:'
I18N_install_launcher_global='Use launcher: %s  (from any project: cd project && %s check)'
