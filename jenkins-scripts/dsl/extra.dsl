import _configs_.*
import javaposse.jobdsl.dsl.Job

Globals.default_emails = "jrivero@osrfoundation.org"

// List of repositories that have a counter part -release repo
// under Open Robotics control that host metadata for debian builds
release_repo_debbuilds = [ 'opensplice' ]

// List of repositories that host branches compatible with gbp (git build
// package) method used by debian
gbp_repo_debbuilds = [ 'ogre-2.1' ]

release_repo_debbuilds.each { software ->
  // --------------------------------------------------------------
  // 1. Create the deb build job
  def build_pkg_job = job("${software}-debbuilder")
  OSRFLinuxBuildPkg.create(build_pkg_job)

  build_pkg_job.with
  {
    // use only the most powerful nodes
    label "large-memory"

    steps {
      shell("""\
            #!/bin/bash -xe

            export USE_ROS_REPO=true
            /bin/bash -x ./scripts/jenkins-scripts/docker/multidistribution-debbuild.bash
            """.stripIndent())
    }
  }
}

gbp_repo_debbuilds.each { software ->
  def build_pkg_job = job("ogre-2.1-debbuilder")
  OSRFLinuxBase.create(build_pkg_job)

  build_pkg_job.with
  {
    // use only the most powerful nodes
    label "large-memory"

    parameters
    {
       stringParam('BRANCH','master',
                   'ogre-2.1-release branch to test')
    }

    scm {
      git {
        remote {
          github('osrf/ogre-2.1-release', 'https')
        }

        extensions {
          cleanBeforeCheckout()
          relativeTargetDirectory('repo')
        }
      }
    }

    logRotator {
      artifactNumToKeep(10)
    }

    concurrentBuild(true)

    throttleConcurrentBuilds {
      maxPerNode(1)
      maxTotal(5)
    }

    wrappers {
      preBuildCleanup {
          includePattern('pkgs/*')
          deleteCommand('sudo rm -rf %s')
      }
    }

    steps {
      shell("""\
            #!/bin/bash -xe

            export LINUX_DISTRO=ubuntu
            export ARCH=${arch}
            export DISTRO=${distro}

            /bin/bash -xe ./scripts/jenkins-scripts/docker/ogre-2.1-debbuild.bash
            """.stripIndent())
    }

    publishers
    {
      publishers {
        archiveArtifacts('pkgs/*')
      }

      downstreamParameterized {
        trigger('repository_uploader_ng') {
          condition('SUCCESS')
          parameters {
            currentBuild()
            predefinedProp("PROJECT_NAME_TO_COPY_ARTIFACTS", "\${JOB_NAME}")
            predefinedProp("DISTRO", "${distro}")
            predefinedProp("ARCH", "${arch}")
            predefinedProp("UPLOAD_TO_REPO", "stable")
            predefinedProp("PACKAGE_ALIAS", "ogre-2.1")
          }
        }
      }

      postBuildScripts {
        steps {
          shell("""\
                #!/bin/bash -xe

                sudo chown -R jenkins \${WORKSPACE}/repo
                sudo chown -R jenkins \${WORKSPACE}/pkgs
                """.stripIndent())
        }

        onlyIfBuildSucceeds(false)
        onlyIfBuildFails(false)
      }
    }
  }
}
