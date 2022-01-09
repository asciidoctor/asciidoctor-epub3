= {project-name}: A _native_ EPUB3 converter for AsciiDoc
Dan Allen <https://github.com/mojavelinux[@mojavelinux]>; Sarah White <https://github.com/graphitefriction[@graphitefriction]>
:project-name: Asciidoctor EPUB3
:project-handle: asciidoctor-epub3
:uri-project: https://github.com/asciidoctor/{project-handle}
:uri-gem: https://rubygems.org/gems/asciidoctor-epub3
:uri-ci: {uri-project}/actions?query=branch%3Amaster
:uri-issues: {uri-project}/issues
:uri-rvm: https://rvm.io

image:https://img.shields.io/badge/zulip-join_chat-brightgreen.svg[project chat,link=https://asciidoctor.zulipchat.com/]
image:https://img.shields.io/gem/v/asciidoctor-epub3.svg[Latest Release,link={uri-gem}]
image:{uri-project}/workflows/CI/badge.svg?branch=master[GitHub Actions,link={uri-ci}]

{project-name} is a set of Asciidoctor extensions for converting AsciiDoc documents directly to the EPUB3 and KF8/MOBI e-book formats.

== Documentation

Detailed installation and usage instructions can be found on the https://docs.asciidoctor.org/epub3-converter/latest/[Asciidoctor Docs site].

== Installation

{project-name} is published on RubyGems.org.
{project-name} requires Ruby 2.3 or newer.
You can install the published gem using the following command:

[source,shell script]
----
$ gem install asciidoctor-epub3
----

Assuming the gem and its dependencies install properly, verify you can run the `{project-handle}` script:

[source,shell script]
----
$ asciidoctor-epub3 -v
----

If you see the version of {project-name} printed, you're ready to use {project-name}.

== Usage

Converting an AsciiDoc document to EPUB3 is as simple as passing your document to the `{project-handle}` command.
This command should be available on your PATH if you installed the `{project-handle}` gem.
Otherwise, you can find the command in the [path]_bin_ folder of the project.
We also recommend specifying an output directory using the `-D` option flag.

[source,shell script]
----
$ asciidoctor-epub3 -D output path/to/book.adoc
----

When the script completes, you'll see the file [file]_book.epub_ appear in the [path]_output_ directory.
Open that file with an EPUB3 reader to view the result.

You may also produce KF8/MOBI file by setting `ebook-format` attribute to `kf8`.

[source,shell script]
----
$ asciidoctor-epub3 -D output -a ebook-format=kf8 path/to/book.adoc
----

When the script completes, the file [file]_book.mobi_ will appear in [path]_output_ directory.

== Contributing

In the spirit of free software, _everyone_ is encouraged to help improve this project.

To contribute code, simply fork the project on GitHub, hack away and send a pull request with your proposed changes.

Feel free to use the {uri-issues}[issue tracker] or {uri-discuss}[Asciidoctor mailing list] to provide feedback or suggestions in other ways.

== Development

To help develop {project-name}, or to simply test drive the development version, you need to get the source from GitHub.
Follow the instructions below to learn how to clone the source and run it from your local copy.

=== Retrieve the Source Code

You can retrieve {project-name} in one of two ways:

. Clone the git repository
. Download a zip archive of the repository

==== Option 1: Fetch Using `git clone`

If you want to clone the git repository, simply copy the {uri-repo}[GitHub repository URL] and pass it to the `git clone` command:

[subs=attributes+]
$ git clone {uri-repo}

Next, change to the project directory:

[subs=attributes+]
$ cd {project-handle}

==== Option 2: Download the Archive

If you want to download a zip archive, click on the btn:[icon:cloud-download[\] Download Zip] button on the right-hand side of the repository page on GitHub.
Once the download finishes, extract the archive, open a console and change to that directory.

TIP: Instead of working out of the {project-handle} directory, you can simply add the absolute path of the [path]_bin_ directory to your `PATH` environment variable.

We'll leverage the project configuration to install the necessary dependencies.

=== Prepare RVM (optional step)

If you're using {uri-rvm}[RVM], we recommend creating a new gemset to work with {project-name}:

 $ rvm use 2.2@asciidoctor-epub3-dev --create

We like RVM because it keeps the dependencies required by various projects isolated.

=== Install the Dependencies

The dependencies needed to use {project-name} are defined in the [file]_Gemfile_ at the root of the project.
We can use Bundler to install the dependencies for us.

To check if you have Bundler available, use the `bundle` command to query the version installed:

 $ bundle --version

If it's not installed, use the `gem` command to install it.

 $ gem install bundler

Then use the `bundle` command to install the project dependencies:

 $ bundle

NOTE: You need to call `bundle` from the project directory so that it can find the [file]_Gemfile_.

=== Build and Install the Gem

Now that the dependencies are installed, you can build and install the gem.

Use the Rake build tool to build and install the gem (into the current RVM gemset or into the system if not using RVM):

 $ rake install:local

The build will report that it built the gem into the [path]_pkg_ directory and that it installed the gem.

Once the development version of the gem is installed, you can run {project-name} by invoking the `asciidoctor-epub3` script:

 $ asciidoctor-epub3 -v

If you see the version of {project-name} printed to your console, you're ready to use {project-name}!

=== Shortcut: Run the Launch Script Directly

Assuming all the required gems install properly, you can run the `asciidoctor-epub3` script directly out of the project folder using either:

 $ bin/asciidoctor-epub3 -v

or

 $ bundle exec bin/asciidoctor-epub3 -v

You're now ready to test drive the development version of {project-name}!

Jump back to <<Getting Started>> to learn how to create an AsciiDoc document and convert it to EPUB3.

=== Fonts

{project-name} embeds a set of fonts and font icons.
The theme's fonts are located in the [path]_data/fonts_ directory.

The M+ Outline fonts are used for titles, headings, literal (monospace) text, and annotation numbers.
The body text uses Noto Serif.
Admonition icons and the end-of-chapter mark are from the Font Awesome icon font.
Refer to the link:NOTICE.adoc[] file for further information about the fonts.

// TODO document command to generate the M+ 1p latin fonts

== Planned Features and Work In Progress

See link:WORKLOG.adoc[].

== Authors

{project-name} was written by https://github.com/mojavelinux[Dan Allen] and https://github.com/graphitefriction[Sarah White] of OpenDevise on behalf of the Asciidoctor Project.

== Copyright

Copyright (C) 2014-2021 OpenDevise Inc. and the Asciidoctor Project.
Free use of this software is granted under the terms of the MIT License.

For the full text of the license, see the link:LICENSE[] file.
Refer to the link:NOTICE.adoc[] file for information about third-party Open Source software in use.
