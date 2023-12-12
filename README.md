Bugs:
- Inserts only linebreak before image (Inherited from pgfexternalize)

Additional ideas:
- add names/IDs of the exts somewhere to the pdf (without using place in the document) so that the user can identify the right pdf/md5 files [maybe this can be used to work on the picture alone by constantly running with the right jobname and viewing the corresponding pdf]

FEATURES:
- implicitly does some deduplication (not quite sute if this is really a positive thing since it happens before macro expansion).
- no massive rebuilds when inserting a picture in the middle (only the new picture should be built)
- should be generic (not only pictures but can externalize everything e.g. huge math envs as well)


STILL OPEN:
- is dealing with duplicates ok this way?
- building extern command -- how can this be done better
- automatically get realjobname -- how is tikzexternal doing this?
-- how to silence extern command? (popen, &>/dev/null ??)
