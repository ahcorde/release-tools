import _configs_.*
import javaposse.jobdsl.dsl.Job

// IGNITION PACKAGES
ignition_software = [ 'cmake',
                      'common',
                      'fuel-tools',
                      'gazebo',
                      'gui',
                      'launch',
                      'math',
                      'msgs',
                      'physics',
                      'plugin',
                      'rendering',
                      'sensors',
                      'tools',
                      'transport',
                      'utils' ]
// DESC: need gpu/display for tests
ignition_gpu                = [ 'gazebo',
                                'gui',
                                'rendering',
                                'sensors' ]
// DESC: software does not have tests
ignition_no_test            = [ 'tools' ]
// DESC: major series supported and released. The branches get CI, install pkg
// testing and debbuild job.
// No branches in ignition_branches means no released branches (only CI on
// main, ABI check, install pkg)
ignition_branches           = [ 'cmake'      : [ '2' ],
                                'common'     : [ '1', '3', '4' ],
                                'fuel-tools' : [ '1', '4', '5', '6' ],
                                'gazebo'     : [ '3', '4', '5' ],
                                'gui'        : [ '0', '3', '4', '5' ],
                                'launch'     : [ '2', '3', '4' ],
                                'math'       : [ '2', '4', '6' ],
                                'msgs'       : [ '1', '5', '6', '7' ],
                                'physics'    : [ '2', '3', '4' ],
                                'plugin'     : [ '1' ],
                                'rendering'  : [ '3', '4', '5' ],
                                'sensors'    : [ '3', '4', '5' ],
                                'tools'      : [ '1' ],
                                'transport'  : [ '4', '8', '9', '10' ],
                                'utils'      : [ '1' ]]
// DESC: prerelease branches are managed as any other supported branches for
// special cases different to major branches: get compilation CI on the branch
// physics/sensors don't need to be included since they use main for gz11
ignition_prerelease_branches = []
// DESC: versioned names to generate debbuild jobs for special cases that
// don't appear in ignition_branches (like nightly builders or 0-debbuild
// jobs for the special cases of foo0 packages)
ignition_extra_debbuild = [ 'cmake3',
                            'common5',
                            'fuel-tools7',
                            'gazebo6',
                            'gui6',
                            'launch5',
                            'math7',
                            'msgs8',
                            'physics5',
                            'plugin2',
                            'rendering6',
                            'sensors6',
                            'tools2',
                            'transport11',
                            'utils1', // see comment https://github.com/ignition-tooling/release-tools/pull/431#issuecomment-815099918
                            'utils2']
// DESC: exclude ignition from generate any install testing job
ignition_no_pkg_yet         = [  ]
// DESC: major versions that has a package in the prerelease repo. Should
// not appear in ignition_no_pkg_yet nor in ignition_branches
ignition_prerelease_pkgs    = [ 'placeholder' : [
                                   '1':  [ 'bionic' ]],
                              ]
// packages using colcon for windows compilation while migrating all them to
// this solution
ignition_colcon_win         = [ 'gazebo',
                                'gui',
                                'launch',
                                'physics',
                                'rendering',
                                'sensors',
                                'transport',
                                'utils' ]

// Main platform using for quick CI
def ci_distro               = Globals.get_ci_distro()
def abi_distro              = Globals.get_abi_distro()
// Other supported platform to be checked but no for quick
// CI integration.
def other_supported_distros = Globals.get_other_supported_distros()
def supported_arches        = Globals.get_supported_arches()

all_supported_distros = ci_distro + other_supported_distros

// Map needed to be used in ci_pr
abi_job_names = [:]

Globals.extra_emails = "caguero@osrfoundation.org"


String ci_distro_str = ci_distro[0]

// Map of lists to use in CIWorkflow
ci_pr_any_list = [:]
ignition_software.each { ign_sw ->
  def list_empty = []
  ci_pr_any_list[ign_sw] = list_empty
}

/**
 * Deeply merges the contents of each Map in sources, merging from
 * "right to left" and returning the merged Map.
 *
 * The source maps will not be modified.
 *
 * Original source code: https://gist.github.com/robhruska/4612278
 */
Map merge_maps(Map[] sources) {
    if (sources.length == 0) return [:]
    if (sources.length == 1) return sources[0]

    sources.inject([:]) { result, source ->
        source.each { k, v ->
            result[k] = result[k] instanceof Map ? merge(result[k], v) : v
        }
        result
    }
}

// return major versions supported or empty if just 0,1 series under
// -dev package.
ArrayList supported_branches(String ign_software)
{
  major_versions_registered = ignition_branches["${ign_software}"]

  if (major_versions_registered == null)
    return [ '' ]

  return major_versions_registered
}

// return prerelease branch names
ArrayList prerelease_branches(String ign_software)
{
  pre_branches = ignition_prerelease_branches["${ign_software}"]

  if (pre_branches == null)
    return [ '' ]

  return pre_branches
}

// return all ci branch names
ArrayList all_branches(String ign_software)
{
  List<String> branches = new ArrayList<String>();
  supported_branches("${ign_software}").each { major_version ->
    if ("${major_version}") {
      branches.add("ign-${ign_software}${major_version}")
    }
  }
  branches.add('main')
  prerelease_branches("${ign_software}").each { branch ->
    if ("${branch}") {
      branches.add(branch)
    }
  }
  return branches
}

//
ArrayList all_debbuilders()
{
  List<String> branches = new ArrayList<String>();
  // add all supported branches
  ignition_software.each { ign_software ->
    supported_branches("${ign_software}").each { major_version ->
      if (major_version) {
        // No 1-debbuild versions, they use the unversioned job
        if ("${major_version}" == "0"  || "${major_version}" == "1" )
          major_version = ""
          branches.add("ign-${ign_software}${major_version}")
      }
    }
  }
  // add all extra debbuilders
  ignition_extra_debbuild.each { ign_name ->
    branches.add("ign-${ign_name}")
  }

  return branches
}

// return all ci branch names
// Map with the form of: major versions as keys.
// Lists of distros supported as values
Map supported_install_pkg_branches(String ign_software)
{
  major_versions_prerelease = ignition_prerelease_pkgs["${ign_software}"]

  // construct a map of stable packages based on supported_branches and
  // all_supported_distros
  map_of_stable_versions = [:]
  map_of_stable_versions[ign_software] = [:]
  supported_branches(ign_software).each { major_version ->
    new_relation = [:]
    new_relation[major_version] = all_supported_distros
    map_of_stable_versions[ign_software] << new_relation
  }

  if (major_versions_prerelease == null)
    return map_of_stable_versions[ign_software];

  return merge_maps(map_of_stable_versions[ign_software],
                    major_versions_prerelease)
}

void include_gpu_label_if_needed(Job job, String ign_software_name)
{
  job.with
  {
    ignition_gpu.each { ign_each ->
      if (ign_software_name == ign_each)
      {
        label "gpu-reliable"

        // unstable build if missing valid gpu display
        publishers {
          consoleParsing {
            projectRules('scripts/jenkins-scripts/parser_rules/display_missing.parser')
            unstableOnWarning()
            failBuildOnError(false)
          }
        }
      }
    }
  }
}

boolean enable_testing(String ign_software_name)
{
  if (ign_software_name in ignition_no_test)
    return false

  return true
}

boolean is_a_colcon_package(String ign_software_name)
{
  if (ign_software_name in ignition_colcon_win)
    return true

  return false
}

// ABI Checker job
// Need to be before the ci-pr_any so the abi job name is defined
ignition_software.each { ign_sw ->
  abi_distro.each { distro ->
    supported_arches.each { arch ->
      // Packages without ABI
      if (ign_sw == 'tools' || ign_sw == 'cmake')
        return

      abi_job_names[ign_sw] = "ignition_${ign_sw}-abichecker-any_to_any-ubuntu_auto-${arch}"
      def abi_job = job(abi_job_names[ign_sw])
      checkout_subdir = "ign-${ign_sw}"
      OSRFLinuxABIGitHub.create(abi_job)
      GenericAnyJobGitHub.create(abi_job,
                        "ignitionrobotics/ign-${ign_sw}",
                        all_branches(ign_sw) - [ 'main'])
      abi_job.with
      {
        if (ign_sw == 'physics')
          label "huge-memory"

        steps {
          shell("""\
                #!/bin/bash -xe
                wget https://raw.githubusercontent.com/osrf/bash-yaml/master/yaml.sh -O yaml.sh
                source yaml.sh

                create_variables \${WORKSPACE}/${checkout_subdir}/bitbucket-pipelines.yml

                export DISTRO=${distro}

                if [[ -n \${image} ]]; then
                  echo "Bitbucket pipeline.yml detected. Default DISTRO is ${distro}"
                  export DISTRO=\$(echo \${image} | sed  's/ubuntu://')
                fi

                export ARCH=${arch}
                export DEST_BRANCH=\${DEST_BRANCH:-\$ghprbTargetBranch}
                export SRC_BRANCH=\${SRC_BRANCH:-\$ghprbSourceBranch}
                export SRC_REPO=\${SRC_REPO:-\$ghprbAuthorRepoGitUrl}
                export ABI_JOB_SOFTWARE_NAME=${checkout_subdir}
                /bin/bash -xe ./scripts/jenkins-scripts/docker/ignition-abichecker.bash
                """.stripIndent())
        } // end of steps
      }  // end of with
    } // end of arch
  } // end of distro
} // end of ignition

// MAIN CI JOBS (check every 5 minutes)
ignition_software.each { ign_sw ->
  supported_arches.each { arch ->
    // --------------------------------------------------------------
    // 1. Create the any job
    def ignition_ci_job_name = "ignition_${ign_sw}-ci-pr_any-ubuntu_auto-${arch}"
    def ignition_ci_any_job = job(ignition_ci_job_name)
    def ignition_checkout_dir = "ign-${ign_sw}"
    OSRFLinuxCompilationAnyGitHub.create(ignition_ci_any_job,
                                        "ignitionrobotics/${ignition_checkout_dir}",
                                         enable_testing(ign_sw))
    include_gpu_label_if_needed(ignition_ci_any_job, ign_sw)
    ignition_ci_any_job.with
    {
      steps
      {
         shell("""\
              #!/bin/bash -xe
              wget https://raw.githubusercontent.com/osrf/bash-yaml/master/yaml.sh -O yaml.sh
              source yaml.sh

              create_variables \${WORKSPACE}/${ignition_checkout_dir}/bitbucket-pipelines.yml

              export DISTRO=${ci_distro_str}

              if [[ -n \${image} ]]; then
                echo "Bitbucket pipeline.yml detected. Default DISTRO is ${ci_distro}"
                export DISTRO=\$(echo \${image} | sed  's/ubuntu://')
              fi

              export ARCH=${arch}

              /bin/bash -xe ./scripts/jenkins-scripts/docker/ign_${ign_sw}-compilation.bash
              """.stripIndent())
      } // end of steps
    } // end of ci_any_job

    // add ci-pr_any to the list for CIWorkflow
    ci_pr_any_list[ign_sw] << ignition_ci_job_name
  }
}

// INSTALL PACKAGE ALL PLATFORMS / DAILY
ignition_software.each { ign_sw ->
  // Exclusion list
  if (ign_sw in ignition_no_pkg_yet)
    return

  supported_arches.each { arch ->
    supported_install_pkg_branches(ign_sw).each { major_version, supported_distros ->
      supported_distros.each { distro ->
        // no bionic for math2 or math3
        if (("${distro}" == "bionic") && (
            (("${ign_sw}" == "math") && ("${major_version}" == "2"))))
          return
        // no xenial support for cmake2 and things that use it
        if (("${distro}" == "xenial") && (
            (("${ign_sw}" == "cmake")      && ("${major_version}" == "2")) ||
            (("${ign_sw}" == "common")     && ("${major_version}" == "3")) ||
            (("${ign_sw}" == "fuel-tools") &&
              (("${major_version}" == "3") || ("${major_version}" == "4") ||
               ("${major_version}" == "5"))) ||
             ("${ign_sw}" == "gazebo")     ||
             ("${ign_sw}" == "gui")        ||
             ("${ign_sw}" == "launch")     ||
            (("${ign_sw}" == "math")       && ("${major_version}" == "6")) ||
            (("${ign_sw}" == "msgs")       &&
              (("${major_version}" == "2") || ("${major_version}" == "3") ||
               ("${major_version}" == "4") || ("${major_version}" == "5") ||
               ("${major_version}" == "6"))) ||
             ("${ign_sw}" == "physics")    ||
             ("${ign_sw}" == "plugin")     ||
             ("${ign_sw}" == "rendering")  ||
             ("${ign_sw}" == "sensors")    ||
            (("${ign_sw}" == "transport")  &&
              (("${major_version}" == "6") || ("${major_version}" == "7") ||
               ("${major_version}" == "8") || ("${major_version}" == "9")))) ||
             ("${ign_sw}" == "utils"))
          return

        extra_repos_str=""
        if ((ign_sw in ignition_prerelease_pkgs) &&
           (major_version in ignition_prerelease_pkgs[ign_sw]) &&
           (distro in ignition_prerelease_pkgs[ign_sw][major_version]))
          extra_repos_str="prerelease"

        // No 1-dev or 0-dev packages (except special cases see
        // ignition_debbuild variable), unversioned
        if ("${major_version}" == "0" || "${major_version}" == "1")
          major_version = ""

        // --------------------------------------------------------------
        def install_default_job = job("ignition_${ign_sw}${major_version}-install-pkg-${distro}-${arch}")
        OSRFLinuxInstall.create(install_default_job)
        include_gpu_label_if_needed(install_default_job, ign_sw)

        install_default_job.with
        {
          triggers {
            cron(Globals.CRON_EVERY_THREE_DAYS)
          }

          def dev_package = "libignition-${ign_sw}${major_version}-dev"
          def gzdev_project = "ignition-${ign_sw}${major_version}"

          steps {
           shell("""\
                 #!/bin/bash -xe

                 export DISTRO=${distro}
                 export ARCH=${arch}
                 export INSTALL_JOB_PKG=${dev_package}
                 export GZDEV_PROJECT_NAME="${gzdev_project}"
                 /bin/bash -x ./scripts/jenkins-scripts/docker/generic-install-test-job.bash
                 """.stripIndent())
          }
        }
      }
    }
  }
}

// OTHER CI SUPPORTED JOBS / DAILY
ignition_software.each { ign_sw ->
  all_supported_distros.each { distro ->
    supported_arches.each { arch ->
      // --------------------------------------------------------------
      // branches CI job scm@daily
      all_branches("${ign_sw}").each { branch ->
        def ignition_ci_job = job("ignition_${ign_sw}-ci-${branch}-${distro}-${arch}")
        OSRFLinuxCompilation.create(ignition_ci_job, enable_testing(ign_sw))
        OSRFGitHub.create(ignition_ci_job,
                              "ignitionrobotics/ign-${ign_sw}",
                              "${branch}", "ign-${ign_sw}")

        include_gpu_label_if_needed(ignition_ci_job, ign_sw)
        ignition_ci_job.with
        {
          triggers {
            scm('@daily')
          }

          // no xenial for ign-physics/sensors/gazebo or plugin main/ign-plugin1
          if (("${distro}" == "xenial") && (
              ("${ign_sw}" == "cmake" && "${branch}" == "ign-cmake2") ||
              ("${ign_sw}" == "cmake" && "${branch}" == "main") ||
              ("${ign_sw}" == "common" && "${branch}" == "main") ||
              ("${ign_sw}" == "common" && "${branch}" == "ign-common3") ||
              ("${ign_sw}" == "fuel-tools" && "${branch}" != "ign-fuel-tools1") ||
              ("${ign_sw}" == "gazebo") ||
              ("${ign_sw}" == "gui") ||
              ("${ign_sw}" == "launch") ||
              ("${ign_sw}" == "math" && "${branch}" == "ign-math6") ||
              ("${ign_sw}" == "math" && "${branch}" == "main") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs2") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs3") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs4") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs5") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs6") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "ign-msgs7") ||
              ("${ign_sw}" == "msgs" && "${branch}" == "main") ||
              ("${ign_sw}" == "physics") ||
              ("${ign_sw}" == "plugin" && "${branch}" != "ign-plugin0") ||
              ("${ign_sw}" == "rendering" && "${branch}" != "ign-rendering0") ||
              ("${ign_sw}" == "sensors") ||
              ("${ign_sw}" == "tools") ||
              ("${ign_sw}" == "transport" && "${branch}" == "ign-transport6") ||
              ("${ign_sw}" == "transport" && "${branch}" == "ign-transport7") ||
              ("${ign_sw}" == "transport" && "${branch}" == "ign-transport8") ||
              ("${ign_sw}" == "transport" && "${branch}" == "ign-transport9") ||
              ("${ign_sw}" == "transport" && "${branch}" == "ign-transport10") ||
              ("${ign_sw}" == "transport" && "${branch}" == "main") ||
              ("${ign_sw}" == "utils")))
            disabled()

          // gz11 branches don't work on xenial
          if (("${branch}" == "gz11") && ("${distro}" == "xenial"))
            disabled()

          steps {
            shell("""\
                  #!/bin/bash -xe

                  export DISTRO=${distro}
                  export ARCH=${arch}
                  /bin/bash -xe ./scripts/jenkins-scripts/docker/ign_${ign_sw}-compilation.bash
                  """.stripIndent())
          }
        }
      }
    }
  }
}

// --------------------------------------------------------------
// DEBBUILD: linux package builder
all_debbuilders().each { debbuilder_name ->
  extra_str = ""
  if (debbuilder_name.contains("gazebo") || debbuilder_name == "transport7")
    extra_str="export NEED_C17_COMPILER=true"

  println("Generating: ${debbuilder_name}-debbuilder")
  def build_pkg_job = job("${debbuilder_name}-debbuilder")
  OSRFLinuxBuildPkg.create(build_pkg_job)
  build_pkg_job.with
  {
      steps {
        shell("""\
              #!/bin/bash -xe

              ${extra_str}
              /bin/bash -x ./scripts/jenkins-scripts/docker/multidistribution-ignition-debbuild.bash
              """.stripIndent())
      }
  }
}

// --------------------------------------------------------------
// BREW: CI jobs

// 1. any job
ignition_software.each { ign_sw ->
  String ignition_brew_ci_any_job_name = "ignition_${ign_sw}-ci-pr_any-homebrew-amd64"
  def ignition_brew_ci_any_job = job(ignition_brew_ci_any_job_name)
  OSRFBrewCompilationAnyGitHub.create(ignition_brew_ci_any_job,
                                      "ignitionrobotics/ign-${ign_sw}",
                                      enable_testing(ign_sw))
  ignition_brew_ci_any_job.with
  {
      steps {
        shell("""\
              #!/bin/bash -xe

              export HOMEBREW_SCRIPT="./scripts/jenkins-scripts/ign_${ign_sw}-default-devel-homebrew-amd64.bash"
              if [ -s "\$HOMEBREW_SCRIPT" ]
              then
                /bin/bash -xe "\$HOMEBREW_SCRIPT"
              else
                /bin/bash -xe "./scripts/jenkins-scripts/lib/project-default-devel-homebrew-amd64.bash" "ignition-${ign_sw}"
              fi
              """.stripIndent())
      }
  }

  // add ci-pr_any to the list for CIWorkflow
  ci_pr_any_list[ign_sw] << ignition_brew_ci_any_job_name

  // 2. main, release branches
  all_branches("${ign_sw}").each { branch ->
    def ignition_brew_ci_job = job("ignition_${ign_sw}-ci-${branch}-homebrew-amd64")
    OSRFBrewCompilation.create(ignition_brew_ci_job, enable_testing(ign_sw))
    OSRFGitHub.create(ignition_brew_ci_job,
                              "ignitionrobotics/ign-${ign_sw}",
                              "${branch}", "ign-${ign_sw}")
    ignition_brew_ci_job.with
    {
        triggers {
          scm('@daily')
        }

        steps {
          shell("""\
                #!/bin/bash -xe

                export HOMEBREW_SCRIPT="./scripts/jenkins-scripts/ign_${ign_sw}-default-devel-homebrew-amd64.bash"
                if [ -s "\$HOMEBREW_SCRIPT" ]
                then
                  /bin/bash -xe "\$HOMEBREW_SCRIPT"
                else
                  /bin/bash -xe "./scripts/jenkins-scripts/lib/project-default-devel-homebrew-amd64.bash" "ignition-${ign_sw}"
                fi
                """.stripIndent())
        }
    }
  }

  // 3. install jobs to test bottles
  supported_install_pkg_branches(ign_sw).each { major_version, supported_distros ->
    def install_default_job = job("ignition_${ign_sw}${major_version}-install_bottle-homebrew-amd64")
    OSRFBrewInstall.create(install_default_job)

    install_default_job.with
    {
      // disable some bottles
      if (("${ign_sw}" == "cmake" && "${major_version}" == "1") ||
          ("${ign_sw}" == "common" && "${major_version}" == "2") ||
          ("${ign_sw}" == "fuel-tools" && "${major_version}" == "2") ||
          ("${ign_sw}" == "gui" && "${major_version}" == "0") ||
          ("${ign_sw}" == "math" && "${major_version}" == "5") ||
          ("${ign_sw}" == "msgs" && "${major_version}" == "2") ||
          ("${ign_sw}" == "transport" && "${major_version}" == "5"))
        disabled()

      triggers {
        cron('@daily')
      }

      def bottle_name = "ignition-${ign_sw}${major_version}"

      steps {
       shell("""\
             #!/bin/bash -xe

             /bin/bash -x ./scripts/jenkins-scripts/lib/project-install-homebrew.bash ${bottle_name}
             """.stripIndent())
      }

      publishers
      {
         configure { project ->
           project / publishers << 'hudson.plugins.logparser.LogParserPublisher' {
              unstableOnWarning true
              failBuildOnError false
              parsingRulesPath('/var/lib/jenkins/logparser_warn_on_mark_unstable')
            }
         }
      }
    }
  }
}

// --------------------------------------------------------------
// WINDOWS: CI job

// 1. any
ignition_software.each { ign_sw ->

  if (is_a_colcon_package(ign_sw)) {
    // colcon uses long paths and windows has a hard limit of 260 chars. Keep
    // names minimal
    ignition_win_ci_any_job_name = "ign_${ign_sw}-pr-win"
    Globals.gazebodistro_branch = true
  } else {
    ignition_win_ci_any_job_name = "ignition_${ign_sw}-ci-pr_any-windows7-amd64"
    Globals.gazebodistro_branch = false
  }

  supported_branches = []
     // ign-gazebo only support windows on main branch
     if (ign_sw == 'gazebo')
       supported_branches = [ 'main' ]

  def ignition_win_ci_any_job = job(ignition_win_ci_any_job_name)
  OSRFWinCompilationAnyGitHub.create(ignition_win_ci_any_job,
                                    "ignitionrobotics/ign-${ign_sw}",
                                    enable_testing(ign_sw),
                                    supported_branches)
  ignition_win_ci_any_job.with
  {
     // ign-launch still not ported completely to Windows
     if (ign_sw == 'launch')
       disabled()

      steps {
        batchFile("""\
              call "./scripts/jenkins-scripts/ign_${ign_sw}-default-devel-windows-amd64.bat"
              """.stripIndent())
      }
  }

  // add ci-pr_any to the list for CIWorkflow
  ci_pr_any_list[ign_sw] << ignition_win_ci_any_job_name

  // 2. main, release branches
  all_branches("${ign_sw}").each { branch ->
    if (is_a_colcon_package(ign_sw)) {
      // colcon uses long paths and windows has a hard limit of 260 chars. Keep
      // names minimal
      if (branch == 'main')
        branch_name = "ci"
      else
        branch_name = branch - ign_sw
      ignition_win_ci_job_name = "ign_${ign_sw}-${branch_name}-win"
    } else {
      ignition_win_ci_job_name = "ignition_${ign_sw}-ci-${branch}-windows7-amd64"
    }

    def ignition_win_ci_job = job(ignition_win_ci_job_name)
    OSRFWinCompilation.create(ignition_win_ci_job, enable_testing(ign_sw))
    OSRFGitHub.create(ignition_win_ci_job,
                              "ignitionrobotics/ign-${ign_sw}",
                              "${branch}", "ign-${ign_sw}")

    ignition_win_ci_job.with
    {
        // ign-gazebo only works in main by now (ign-gazebo5)
        if (ign_sw == 'gazebo' && branch != 'main')
          disabled()

        // ign-launch still not ported completely to Windows
        if (ign_sw == 'launch')
          disabled()

        triggers {
          scm('@daily')
        }

        steps {
          batchFile("""\
                call "./scripts/jenkins-scripts/ign_${ign_sw}-default-devel-windows-amd64.bat"
                """.stripIndent())
        }
    }
  }
}

// Main CI workflow
ignition_software.each { ign_sw ->
  def String ci_main_name = "ignition_${ign_sw}-ci-manual_any"
  def ign_ci_main = pipelineJob(ci_main_name)
  OSRFCIWorkFlowMultiAnyGitHub.create(ign_ci_main, ci_pr_any_list[ign_sw])
}
