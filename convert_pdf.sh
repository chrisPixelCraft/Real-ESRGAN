gs -sDEVICE=pdfwrite \
   -dDEVICEWIDTHPOINTS=147.4 \
   -dDEVICEHEIGHTPOINTS=425.2 \
   -dPDFFitPage \
   -dFIXEDMEDIA \
   -dColorImageResolution=300 \
   -dGrayImageResolution=300 \
   -dMonoImageResolution=300 \
   -dCompatibilityLevel=1.4 \
   -o output_combined.pdf \
   results_bookmarks_simple/combined.pdf
