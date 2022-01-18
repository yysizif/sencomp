# Title TBD

Please refer to the PSTA [article][psta].  This repository contains
coder prototypes in Perl5 and test data used in the article.

  [psta]: http://psta.psiras.ru/read/psta2022_TBD.pdf

To run all tests found in the article, you should also download test
data from EMBED project data site
[http://embed-dataset.org](http://embed-dataset.org).  Download the
following three files with *"Ground truth plug load consumption"* data:

    % wc -c *.zip
     26825002 Apt1_GT_Plug.zip
     54172382 Apt2_GT_Plug.zip
     28561226 Apt3_GT_Plug.zip
    109558610 total

    % md5sum *.zip
    eb96d8b967727e71aa5ae03979a81940  Apt1_GT_Plug.zip
    78f8ec041ba45afa07c430fbad140b3b  Apt2_GT_Plug.zip
    6fb3663e4422a201ec704915326b9c20  Apt3_GT_Plug.zip

Say ```make``` to run all tests.  This is known to work in Debian 10
Buster on AMD64, but hopefully any GNU/Linux on any CPU architecture
will do.  After some **hours** (yes: EMBED data are bulky while coder
prototypes are not written for efficiency) you should obtain results
in ```grandtab-1.tex``` and ```grandtab-2.tex```.  If you have
```pdflatex``` installed, ```make``` will also build
```grandtab.pdf``` containing formatted table of results.

```make``` outputs command lines for each test as it runs, e.g.

    cat 'embed/Apt1_GT_Plug/Iron.csv' | embed/from-csv.pl | ./rlgr.pl -18 -k10 -L256 

If you execute the command line outside of ```make``` you will see
data points being compressed, the codewords generated and some
auxiliary output specific for each coder.
