# The tools prepare-image.sh needs: debugfs (e2fsprogs-extra), tune2fs and e2fsck 1.47+ (the image
# uses orphan_file), sfdisk, openssl. Built locally by prepare.sh; it never runs with network access.
FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
RUN apk add --no-cache bash e2fsprogs e2fsprogs-extra sfdisk openssl
COPY prepare-image.sh /usr/local/bin/prepare-image.sh
# Not COPY --chmod: that needs BuildKit. A checkout made under umask 077 leaves the script 0700.
RUN chmod 0755 /usr/local/bin/prepare-image.sh
# prepare.sh runs it as the user's own uid:gid; nobody, should it ever be started without --user.
USER 65534:65534
# A one-shot job, not a service: there is nothing to check while it runs.
HEALTHCHECK NONE
ENTRYPOINT ["/usr/local/bin/prepare-image.sh"]
