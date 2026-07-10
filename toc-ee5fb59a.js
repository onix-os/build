// Populate the sidebar
//
// This is a script, and not included directly in the page, to control the total size of the book.
// The TOC contains an entry for each page, so if each page includes a copy of the TOC,
// the total size of the page becomes O(n**2).
class MDBookSidebarScrollbox extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        this.innerHTML = '<ol class="chapter"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/INTRODUCTION.html">Introduction</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/QUICKSTART.html">Quickstart</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="ARCHITECTURE.html">Architecture</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/RECIPES.html">Recipes</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="packages/STONES.html">Stone catalog</a></span></li><li class="chapter-item expanded "><li class="part-title">Learning phases</li></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/phase_0_forge_vm_and_first_stone.html"><strong aria-hidden="true">1.</strong> Phase 0 — forge VM and first .stone</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/000_validate.html"><strong aria-hidden="true">1.1.</strong> 000 — validate</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/001_passwordless_disk_builder.html"><strong aria-hidden="true">1.2.</strong> 001 — passwordless disk builder</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/002_build_forge_disk.html"><strong aria-hidden="true">1.3.</strong> 002 — build the forge disk</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/003_boot_forge.html"><strong aria-hidden="true">1.4.</strong> 003 — boot the forge</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/004_provision_tools.html"><strong aria-hidden="true">1.5.</strong> 004 — provision tools</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/005_first_stone.html"><strong aria-hidden="true">1.6.</strong> 005 — first .stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase0/docs/006_moss_state_smoke_test.html"><strong aria-hidden="true">1.7.</strong> 006 — real Moss state smoke test</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/phase_1_first_real_onix_stones.html"><strong aria-hidden="true">2.</strong> Phase 1 — first real ONIX stones</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/100_forge_readiness.html"><strong aria-hidden="true">2.1.</strong> 100 — forge readiness</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/101_build_onix_branding.html"><strong aria-hidden="true">2.2.</strong> 101 — build branding</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/102_build_onix_filesystem.html"><strong aria-hidden="true">2.3.</strong> 102 — build filesystem</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/103_assemble_first_named_local_onix_repo.html"><strong aria-hidden="true">2.4.</strong> 103 — assemble first named local ONIX repo</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/104_prepare_publishable_repo_layout.html"><strong aria-hidden="true">2.5.</strong> 104 — prepare publishable ONIX repo layout</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/105_export_publishable_repo_to_host.html"><strong aria-hidden="true">2.6.</strong> 105 — export publishable repo to the host</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/106_verify_exported_host_artifact.html"><strong aria-hidden="true">2.7.</strong> 106 — verify exported host artifact</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/107_verify_no_upload_publishing_plan.html"><strong aria-hidden="true">2.8.</strong> 107 — verify no-upload publishing plan</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase1/docs/108_preview_publication_without_upload.html"><strong aria-hidden="true">2.9.</strong> 108 — preview publication without upload</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/phase_2_first_bootable_onix_image.html"><strong aria-hidden="true">3.</strong> Phase 2 — first bootable ONIX image</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/200_image_assembly_readiness.html"><strong aria-hidden="true">3.1.</strong> 200 — image assembly readiness</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/201_assemble_first_onix_root_tree.html"><strong aria-hidden="true">3.2.</strong> 201 — assemble the first ONIX root tree</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/202_build_host_side_moss.html"><strong aria-hidden="true">3.3.</strong> 202 — build host-side Moss</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/203_assemble_root_tree_with_host_moss_only.html"><strong aria-hidden="true">3.4.</strong> 203 — assemble the root tree with host-side Moss only</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/204_image_disk_assembly_contract.html"><strong aria-hidden="true">3.5.</strong> 204 — define image/disk assembly contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/205_create_non_booting_disk_root_skeleton.html"><strong aria-hidden="true">3.6.</strong> 205 — create first non-booting disk/root skeleton</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/206_install_systemd_boot_bls_skeleton.html"><strong aria-hidden="true">3.7.</strong> 206 — install the systemd-boot/BLS skeleton</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/207_kernel_initramfs_contract.html"><strong aria-hidden="true">3.8.</strong> 207 — kernel + initramfs contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/208_systemd_userspace_contract.html"><strong aria-hidden="true">3.9.</strong> 208 — systemd userspace contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/209_systemd_on_musl_feasibility_gate.html"><strong aria-hidden="true">3.10.</strong> 209 — systemd-on-musl feasibility gate</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/210_init_path_decision_contract.html"><strong aria-hidden="true">3.11.</strong> 210 — init path decision contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/211_first_kernel_initramfs_payload.html"><strong aria-hidden="true">3.12.</strong> 211 — first kernel + initramfs payload</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/212_first_qemu_boot_probe.html"><strong aria-hidden="true">3.13.</strong> 212 — first QEMU boot probe</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/213_first_musl_systemd_userspace_payload.html"><strong aria-hidden="true">3.14.</strong> 213 — first musl systemd userspace payload</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase2/docs/214_first_kernel_module_kmod_payload.html"><strong aria-hidden="true">3.15.</strong> 214 — first kernel module/kmod payload</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase3/docs/phase_3_reserved_onix_owned_kernel_work.html"><strong aria-hidden="true">4.</strong> Phase 3 — reserved ONIX-owned kernel work</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase3/docs/300_deferred_kernel_ownership_contract.html"><strong aria-hidden="true">4.1.</strong> 300 — deferred kernel ownership contract</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/phase_4_booted_onix_base_userspace.html"><strong aria-hidden="true">5.</strong> Phase 4 — booted ONIX base userspace</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/400_booted_base_readiness.html"><strong aria-hidden="true">5.1.</strong> 400 — booted-base readiness</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/401_materialize_live_etc.html"><strong aria-hidden="true">5.2.</strong> 401 — materialize live /etc</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/402_base_users_groups_shell_policy.html"><strong aria-hidden="true">5.3.</strong> 402 — base users, groups, and shell policy</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/403_bootstrap_serial_root_console_proof.html"><strong aria-hidden="true">5.4.</strong> 403 — bootstrap serial root console proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/404_minimal_qemu_user_networking_proof.html"><strong aria-hidden="true">5.5.</strong> 404 — minimal QEMU user networking proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/405_host_to_guest_tcp_inspection_proof.html"><strong aria-hidden="true">5.6.</strong> 405 — host-to-guest TCP inspection proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/406_authenticated_ssh_proof.html"><strong aria-hidden="true">5.7.</strong> 406 — authenticated SSH proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/407_machine_plane_ownership_audit.html"><strong aria-hidden="true">5.8.</strong> 407 — machine-plane ownership audit</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/408_local_stone_repo_contract.html"><strong aria-hidden="true">5.9.</strong> 408 — local stone/repo contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/409_build_onix_busybox_stone.html"><strong aria-hidden="true">5.10.</strong> 409 — build busybox.stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/410_install_use_onix_busybox.html"><strong aria-hidden="true">5.11.</strong> 410 — install/use busybox</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/411_boot_prove_onix_busybox.html"><strong aria-hidden="true">5.12.</strong> 411 — boot-prove busybox</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/412_build_onix_dropbear_stone.html"><strong aria-hidden="true">5.13.</strong> 412 — build dropbear.stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/413_install_use_onix_dropbear.html"><strong aria-hidden="true">5.14.</strong> 413 — install/use dropbear</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/414_systemd_ownership_audit.html"><strong aria-hidden="true">5.15.</strong> 414 — systemd ownership audit</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/415_build_onix_systemd_stone.html"><strong aria-hidden="true">5.16.</strong> 415 — build systemd.stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/416_install_use_onix_systemd.html"><strong aria-hidden="true">5.17.</strong> 416 — install/use systemd</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/417_boot_prove_onix_systemd.html"><strong aria-hidden="true">5.18.</strong> 417 — boot-prove systemd</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/418_package_prove_bootstrap.html"><strong aria-hidden="true">5.19.</strong> 418 — package/prove bootstrap</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/419_booted_base_ownership_audit.html"><strong aria-hidden="true">5.20.</strong> 419 — booted-base ownership audit</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/420_prune_stale_old_nix_busybox_dropbear_payloads.html"><strong aria-hidden="true">5.21.</strong> 420 — prune stale old nix BusyBox/Dropbear payloads</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/421_prepare_native_onix_systemd.html"><strong aria-hidden="true">5.22.</strong> 421 — prepare native systemd</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/422_native_onix_systemd_build_install_boot_proof.html"><strong aria-hidden="true">5.23.</strong> 422 — native systemd build/install/boot proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/424_bring_up_native_onix_for_inspection.html"><strong aria-hidden="true">5.24.</strong> 424 — bring up native ONIX for inspection</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase4/docs/425_final_phase_4_acceptance_check.html"><strong aria-hidden="true">5.25.</strong> 425 — final Phase 4 acceptance check</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/phase_5_rust_first_musl_package_repository_plane.html"><strong aria-hidden="true">6.</strong> Phase 5 — Rust-first musl package/repository plane</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/500_rust_first_musl_only_static_first_package_law.html"><strong aria-hidden="true">6.1.</strong> 500 — Rust-first musl-only static-first package law</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/501_canonical_package_layout_metadata_contract.html"><strong aria-hidden="true">6.2.</strong> 501 — canonical package layout and metadata contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/502_runtime_clean_stone_payload_audit_helper.html"><strong aria-hidden="true">6.3.</strong> 502 — runtime-clean stone payload audit helper</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/503_copy_existing_recipes_into_canonical_package_layout.html"><strong aria-hidden="true">6.4.</strong> 503 — copy existing recipes into canonical package layout</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/504_canonical_essential_package_build_lane.html"><strong aria-hidden="true">6.5.</strong> 504 — canonical essential package build lane</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/505_canonical_local_onix_package_repo.html"><strong aria-hidden="true">6.6.</strong> 505 — canonical local ONIX package repo</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/506_essential_package_ownership_collision_fix.html"><strong aria-hidden="true">6.7.</strong> 506 — essential package ownership collision fix</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/507_canonical_repo_image_consumption.html"><strong aria-hidden="true">6.8.</strong> 507 — canonical repo image consumption</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/508_local_public_repository_layout.html"><strong aria-hidden="true">6.9.</strong> 508 — local public repository layout</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/509_first_rust_essential_stones.html"><strong aria-hidden="true">6.10.</strong> 509 — first Rust essential stones</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/510_privilege_shared_library_surface.html"><strong aria-hidden="true">6.11.</strong> 510 — privilege shared-library surface</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/511_rootasrole_privilege_stone.html"><strong aria-hidden="true">6.12.</strong> 511 — RootAsRole privilege stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/512_rootasrole_integrated_policy.html"><strong aria-hidden="true">6.13.</strong> 512 — RootAsRole integrated policy</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/513_uutils_command_ownership.html"><strong aria-hidden="true">6.14.</strong> 513 — uutils command ownership</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/514_booted_phase_5_runtime_proof.html"><strong aria-hidden="true">6.15.</strong> 514 — booted Phase 5 runtime proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/515_moss_runtime_package_and_self_repo_probe.html"><strong aria-hidden="true">6.16.</strong> 515 — moss runtime package and self-repo probe</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/516_busybox_sh_and_fish_shell_policy.html"><strong aria-hidden="true">6.17.</strong> 516 — BusyBox sh and fish shell policy</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/517_fish_shell_stone.html"><strong aria-hidden="true">6.18.</strong> 517 — fish shell stone</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase5/docs/518_default_login_shell_runtime_proof.html"><strong aria-hidden="true">6.19.</strong> 518 — default login shell runtime proof</a></span></li></ol><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/phase_6_nix_toolbox_plane.html"><strong aria-hidden="true">7.</strong> Phase 6 — nix toolbox plane</a></span><ol class="section"><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/600_nix_architecture_contract.html"><strong aria-hidden="true">7.1.</strong> 600 — nix architecture contract</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/601_persistent_nix_store_and_users.html"><strong aria-hidden="true">7.2.</strong> 601 — persistent /nix store and users</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/602_nix_stone_package.html"><strong aria-hidden="true">7.3.</strong> 602 — nix stone package</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/603_nix_daemon_config_shell_integration.html"><strong aria-hidden="true">7.4.</strong> 603 — nix daemon, config, and shell integration</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/604_offline_multi_user_nix_proof.html"><strong aria-hidden="true">7.5.</strong> 604 — offline multi-user nix proof</a></span></li><li class="chapter-item expanded "><span class="chapter-link-wrapper"><a href="vm/phase6/docs/605_online_flakes_substituter_acceptance.html"><strong aria-hidden="true">7.6.</strong> 605 — online flakes and substituter acceptance</a></span></li></ol></li></ol>';
        // Set the current, active page, and reveal it if it's hidden
        let current_page = document.location.href.toString().split('#')[0].split('?')[0];
        if (current_page.endsWith('/')) {
            current_page += 'index.html';
        }
        const links = Array.prototype.slice.call(this.querySelectorAll('a'));
        const l = links.length;
        for (let i = 0; i < l; ++i) {
            const link = links[i];
            const href = link.getAttribute('href');
            if (href && !href.startsWith('#') && !/^(?:[a-z+]+:)?\/\//.test(href)) {
                link.href = path_to_root + href;
            }
            // The 'index' page is supposed to alias the first chapter in the book.
            // Check both with and without the '.html' suffix to be robust against pretty URLs
            if (link.href.replace(/\.html$/, '') === current_page.replace(/\.html$/, '')
                || i === 0
                && path_to_root === ''
                && current_page.endsWith('/index.html')) {
                link.classList.add('active');
                let parent = link.parentElement;
                while (parent) {
                    if (parent.tagName === 'LI' && parent.classList.contains('chapter-item')) {
                        parent.classList.add('expanded');
                    }
                    parent = parent.parentElement;
                }
            }
        }
        // Track and set sidebar scroll position
        this.addEventListener('click', e => {
            if (e.target.tagName === 'A') {
                const clientRect = e.target.getBoundingClientRect();
                const sidebarRect = this.getBoundingClientRect();
                sessionStorage.setItem('sidebar-scroll-offset', clientRect.top - sidebarRect.top);
            }
        }, { passive: true });
        const sidebarScrollOffset = sessionStorage.getItem('sidebar-scroll-offset');
        sessionStorage.removeItem('sidebar-scroll-offset');
        if (sidebarScrollOffset !== null) {
            // preserve sidebar scroll position when navigating via links within sidebar
            const activeSection = this.querySelector('.active');
            if (activeSection) {
                const clientRect = activeSection.getBoundingClientRect();
                const sidebarRect = this.getBoundingClientRect();
                const currentOffset = clientRect.top - sidebarRect.top;
                this.scrollTop += currentOffset - parseFloat(sidebarScrollOffset);
            }
        } else {
            // scroll sidebar to current active section when navigating via
            // 'next/previous chapter' buttons
            const activeSection = document.querySelector('#mdbook-sidebar .active');
            if (activeSection) {
                activeSection.scrollIntoView({ block: 'center' });
            }
        }
        // Toggle buttons
        const sidebarAnchorToggles = document.querySelectorAll('.chapter-fold-toggle');
        function toggleSection(ev) {
            ev.currentTarget.parentElement.parentElement.classList.toggle('expanded');
        }
        Array.from(sidebarAnchorToggles).forEach(el => {
            el.addEventListener('click', toggleSection);
        });
    }
}
window.customElements.define('mdbook-sidebar-scrollbox', MDBookSidebarScrollbox);


// ---------------------------------------------------------------------------
// Support for dynamically adding headers to the sidebar.

(function() {
    // This is used to detect which direction the page has scrolled since the
    // last scroll event.
    let lastKnownScrollPosition = 0;
    // This is the threshold in px from the top of the screen where it will
    // consider a header the "current" header when scrolling down.
    const defaultDownThreshold = 150;
    // Same as defaultDownThreshold, except when scrolling up.
    const defaultUpThreshold = 300;
    // The threshold is a virtual horizontal line on the screen where it
    // considers the "current" header to be above the line. The threshold is
    // modified dynamically to handle headers that are near the bottom of the
    // screen, and to slightly offset the behavior when scrolling up vs down.
    let threshold = defaultDownThreshold;
    // This is used to disable updates while scrolling. This is needed when
    // clicking the header in the sidebar, which triggers a scroll event. It
    // is somewhat finicky to detect when the scroll has finished, so this
    // uses a relatively dumb system of disabling scroll updates for a short
    // time after the click.
    let disableScroll = false;
    // Array of header elements on the page.
    let headers;
    // Array of li elements that are initially collapsed headers in the sidebar.
    // I'm not sure why eslint seems to have a false positive here.
    // eslint-disable-next-line prefer-const
    let headerToggles = [];
    // This is a debugging tool for the threshold which you can enable in the console.
    let thresholdDebug = false;

    // Updates the threshold based on the scroll position.
    function updateThreshold() {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const windowHeight = window.innerHeight;
        const documentHeight = document.documentElement.scrollHeight;

        // The number of pixels below the viewport, at most documentHeight.
        // This is used to push the threshold down to the bottom of the page
        // as the user scrolls towards the bottom.
        const pixelsBelow = Math.max(0, documentHeight - (scrollTop + windowHeight));
        // The number of pixels above the viewport, at least defaultDownThreshold.
        // Similar to pixelsBelow, this is used to push the threshold back towards
        // the top when reaching the top of the page.
        const pixelsAbove = Math.max(0, defaultDownThreshold - scrollTop);
        // How much the threshold should be offset once it gets close to the
        // bottom of the page.
        const bottomAdd = Math.max(0, windowHeight - pixelsBelow - defaultDownThreshold);
        let adjustedBottomAdd = bottomAdd;

        // Adjusts bottomAdd for a small document. The calculation above
        // assumes the document is at least twice the windowheight in size. If
        // it is less than that, then bottomAdd needs to be shrunk
        // proportional to the difference in size.
        if (documentHeight < windowHeight * 2) {
            const maxPixelsBelow = documentHeight - windowHeight;
            const t = 1 - pixelsBelow / Math.max(1, maxPixelsBelow);
            const clamp = Math.max(0, Math.min(1, t));
            adjustedBottomAdd *= clamp;
        }

        let scrollingDown = true;
        if (scrollTop < lastKnownScrollPosition) {
            scrollingDown = false;
        }

        if (scrollingDown) {
            // When scrolling down, move the threshold up towards the default
            // downwards threshold position. If near the bottom of the page,
            // adjustedBottomAdd will offset the threshold towards the bottom
            // of the page.
            const amountScrolledDown = scrollTop - lastKnownScrollPosition;
            const adjustedDefault = defaultDownThreshold + adjustedBottomAdd;
            threshold = Math.max(adjustedDefault, threshold - amountScrolledDown);
        } else {
            // When scrolling up, move the threshold down towards the default
            // upwards threshold position. If near the bottom of the page,
            // quickly transition the threshold back up where it normally
            // belongs.
            const amountScrolledUp = lastKnownScrollPosition - scrollTop;
            const adjustedDefault = defaultUpThreshold - pixelsAbove
                + Math.max(0, adjustedBottomAdd - defaultDownThreshold);
            threshold = Math.min(adjustedDefault, threshold + amountScrolledUp);
        }

        if (documentHeight <= windowHeight) {
            threshold = 0;
        }

        if (thresholdDebug) {
            const id = 'mdbook-threshold-debug-data';
            let data = document.getElementById(id);
            if (data === null) {
                data = document.createElement('div');
                data.id = id;
                data.style.cssText = `
                    position: fixed;
                    top: 50px;
                    right: 10px;
                    background-color: 0xeeeeee;
                    z-index: 9999;
                    pointer-events: none;
                `;
                document.body.appendChild(data);
            }
            data.innerHTML = `
                <table>
                  <tr><td>documentHeight</td><td>${documentHeight.toFixed(1)}</td></tr>
                  <tr><td>windowHeight</td><td>${windowHeight.toFixed(1)}</td></tr>
                  <tr><td>scrollTop</td><td>${scrollTop.toFixed(1)}</td></tr>
                  <tr><td>pixelsAbove</td><td>${pixelsAbove.toFixed(1)}</td></tr>
                  <tr><td>pixelsBelow</td><td>${pixelsBelow.toFixed(1)}</td></tr>
                  <tr><td>bottomAdd</td><td>${bottomAdd.toFixed(1)}</td></tr>
                  <tr><td>adjustedBottomAdd</td><td>${adjustedBottomAdd.toFixed(1)}</td></tr>
                  <tr><td>scrollingDown</td><td>${scrollingDown}</td></tr>
                  <tr><td>threshold</td><td>${threshold.toFixed(1)}</td></tr>
                </table>
            `;
            drawDebugLine();
        }

        lastKnownScrollPosition = scrollTop;
    }

    function drawDebugLine() {
        if (!document.body) {
            return;
        }
        const id = 'mdbook-threshold-debug-line';
        const existingLine = document.getElementById(id);
        if (existingLine) {
            existingLine.remove();
        }
        const line = document.createElement('div');
        line.id = id;
        line.style.cssText = `
            position: fixed;
            top: ${threshold}px;
            left: 0;
            width: 100vw;
            height: 2px;
            background-color: red;
            z-index: 9999;
            pointer-events: none;
        `;
        document.body.appendChild(line);
    }

    function mdbookEnableThresholdDebug() {
        thresholdDebug = true;
        updateThreshold();
        drawDebugLine();
    }

    window.mdbookEnableThresholdDebug = mdbookEnableThresholdDebug;

    // Updates which headers in the sidebar should be expanded. If the current
    // header is inside a collapsed group, then it, and all its parents should
    // be expanded.
    function updateHeaderExpanded(currentA) {
        // Add expanded to all header-item li ancestors.
        let current = currentA.parentElement;
        while (current) {
            if (current.tagName === 'LI' && current.classList.contains('header-item')) {
                current.classList.add('expanded');
            }
            current = current.parentElement;
        }
    }

    // Updates which header is marked as the "current" header in the sidebar.
    // This is done with a virtual Y threshold, where headers at or below
    // that line will be considered the current one.
    function updateCurrentHeader() {
        if (!headers || !headers.length) {
            return;
        }

        // Reset the classes, which will be rebuilt below.
        const els = document.getElementsByClassName('current-header');
        for (const el of els) {
            el.classList.remove('current-header');
        }
        for (const toggle of headerToggles) {
            toggle.classList.remove('expanded');
        }

        // Find the last header that is above the threshold.
        let lastHeader = null;
        for (const header of headers) {
            const rect = header.getBoundingClientRect();
            if (rect.top <= threshold) {
                lastHeader = header;
            } else {
                break;
            }
        }
        if (lastHeader === null) {
            lastHeader = headers[0];
            const rect = lastHeader.getBoundingClientRect();
            const windowHeight = window.innerHeight;
            if (rect.top >= windowHeight) {
                return;
            }
        }

        // Get the anchor in the summary.
        const href = '#' + lastHeader.id;
        const a = [...document.querySelectorAll('.header-in-summary')]
            .find(element => element.getAttribute('href') === href);
        if (!a) {
            return;
        }

        a.classList.add('current-header');

        updateHeaderExpanded(a);
    }

    // Updates which header is "current" based on the threshold line.
    function reloadCurrentHeader() {
        if (disableScroll) {
            return;
        }
        updateThreshold();
        updateCurrentHeader();
    }


    // When clicking on a header in the sidebar, this adjusts the threshold so
    // that it is located next to the header. This is so that header becomes
    // "current".
    function headerThresholdClick(event) {
        // See disableScroll description why this is done.
        disableScroll = true;
        setTimeout(() => {
            disableScroll = false;
        }, 100);
        // requestAnimationFrame is used to delay the update of the "current"
        // header until after the scroll is done, and the header is in the new
        // position.
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                // Closest is needed because if it has child elements like <code>.
                const a = event.target.closest('a');
                const href = a.getAttribute('href');
                const targetId = href.substring(1);
                const targetElement = document.getElementById(targetId);
                if (targetElement) {
                    threshold = targetElement.getBoundingClientRect().bottom;
                    updateCurrentHeader();
                }
            });
        });
    }

    // Takes the nodes from the given head and copies them over to the
    // destination, along with some filtering.
    function filterHeader(source, dest) {
        const clone = source.cloneNode(true);
        clone.querySelectorAll('mark').forEach(mark => {
            mark.replaceWith(...mark.childNodes);
        });
        dest.append(...clone.childNodes);
    }

    // Scans page for headers and adds them to the sidebar.
    document.addEventListener('DOMContentLoaded', function() {
        const activeSection = document.querySelector('#mdbook-sidebar .active');
        if (activeSection === null) {
            return;
        }

        const main = document.getElementsByTagName('main')[0];
        headers = Array.from(main.querySelectorAll('h2, h3, h4, h5, h6'))
            .filter(h => h.id !== '' && h.children.length && h.children[0].tagName === 'A');

        if (headers.length === 0) {
            return;
        }

        // Build a tree of headers in the sidebar.

        const stack = [];

        const firstLevel = parseInt(headers[0].tagName.charAt(1));
        for (let i = 1; i < firstLevel; i++) {
            const ol = document.createElement('ol');
            ol.classList.add('section');
            if (stack.length > 0) {
                stack[stack.length - 1].ol.appendChild(ol);
            }
            stack.push({level: i + 1, ol: ol});
        }

        // The level where it will start folding deeply nested headers.
        const foldLevel = 3;

        for (let i = 0; i < headers.length; i++) {
            const header = headers[i];
            const level = parseInt(header.tagName.charAt(1));

            const currentLevel = stack[stack.length - 1].level;
            if (level > currentLevel) {
                // Begin nesting to this level.
                for (let nextLevel = currentLevel + 1; nextLevel <= level; nextLevel++) {
                    const ol = document.createElement('ol');
                    ol.classList.add('section');
                    const last = stack[stack.length - 1];
                    const lastChild = last.ol.lastChild;
                    // Handle the case where jumping more than one nesting
                    // level, which doesn't have a list item to place this new
                    // list inside of.
                    if (lastChild) {
                        lastChild.appendChild(ol);
                    } else {
                        last.ol.appendChild(ol);
                    }
                    stack.push({level: nextLevel, ol: ol});
                }
            } else if (level < currentLevel) {
                while (stack.length > 1 && stack[stack.length - 1].level > level) {
                    stack.pop();
                }
            }

            const li = document.createElement('li');
            li.classList.add('header-item');
            li.classList.add('expanded');
            if (level < foldLevel) {
                li.classList.add('expanded');
            }
            const span = document.createElement('span');
            span.classList.add('chapter-link-wrapper');
            const a = document.createElement('a');
            span.appendChild(a);
            a.href = '#' + header.id;
            a.classList.add('header-in-summary');
            filterHeader(header.children[0], a);
            a.addEventListener('click', headerThresholdClick);
            const nextHeader = headers[i + 1];
            if (nextHeader !== undefined) {
                const nextLevel = parseInt(nextHeader.tagName.charAt(1));
                if (nextLevel > level && level >= foldLevel) {
                    const toggle = document.createElement('a');
                    toggle.classList.add('chapter-fold-toggle');
                    toggle.classList.add('header-toggle');
                    toggle.addEventListener('click', () => {
                        li.classList.toggle('expanded');
                    });
                    const toggleDiv = document.createElement('div');
                    toggleDiv.textContent = '❱';
                    toggle.appendChild(toggleDiv);
                    span.appendChild(toggle);
                    headerToggles.push(li);
                }
            }
            li.appendChild(span);

            const currentParent = stack[stack.length - 1];
            currentParent.ol.appendChild(li);
        }

        const onThisPage = document.createElement('div');
        onThisPage.classList.add('on-this-page');
        onThisPage.append(stack[0].ol);
        const activeItemSpan = activeSection.parentElement;
        activeItemSpan.after(onThisPage);
    });

    document.addEventListener('DOMContentLoaded', reloadCurrentHeader);
    document.addEventListener('scroll', reloadCurrentHeader, { passive: true });
})();

