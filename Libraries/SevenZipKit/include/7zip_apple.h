#ifndef SEVENZIP_APPLE_H
#define SEVENZIP_APPLE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * 7zip-apple: C FFI wrapper for 7-Zip (macOS)
 *
 * Wraps 7-Zip identically to 7zz: each call builds the switches 7zz would
 * be given, parses them with 7zz's own command-line parser into the same
 * options, and runs the same Extract() / UpdateArchive() entry points.
 * Only the console layer is replaced: progress, item names and errors come
 * back through callbacks and return codes instead of printed text, and a
 * password never appears in any process's argument list.
 *
 * Every call is synchronous; run it off the main thread. Strings are UTF-8,
 * paths are absolute.
 */

#ifdef __cplusplus
extern "C" {
#endif

/* ═══════════════════════════════════════════════════════════════
 * Return codes
 * ═══════════════════════════════════════════════════════════════ */
#define SEVENZIP_OK                       0
#define SEVENZIP_WARNING                  1   /* finished; some files could not be read or had warnings */
#define SEVENZIP_ERR_INVALID_PARAM       -1
#define SEVENZIP_ERR_NOT_ARCHIVE         -2
#define SEVENZIP_ERR_PASSWORD_REQUIRED   -3
#define SEVENZIP_ERR_WRONG_PASSWORD      -4
#define SEVENZIP_ERR_CANCELLED           -5
#define SEVENZIP_ERR_UNSUPPORTED         -6
#define SEVENZIP_ERR_DATA                -7   /* CRC, data or headers error in the archive */
#define SEVENZIP_ERR_NO_MEMORY           -8
#define SEVENZIP_ERR_FAILED              -9   /* anything else; see sevenzip_last_error() */

/* ═══════════════════════════════════════════════════════════════
 * Extraction overwrite policy (7zz -aoa / -aou / -aos)
 * ═══════════════════════════════════════════════════════════════ */
#define SEVENZIP_OVERWRITE  0
#define SEVENZIP_RENAME     1
#define SEVENZIP_SKIP       2

/* ═══════════════════════════════════════════════════════════════
 * Callbacks — all optional; called on the calling thread
 * ═══════════════════════════════════════════════════════════════ */
typedef struct {
    void *context;
    /* Bytes done of total. Return true to cancel the operation. */
    bool (*progress)(void *context, uint64_t completed, uint64_t total);
    /* The item now being processed: its path inside the archive
       (extract, test, delete) or on disk (update). */
    void (*item)(void *context, const char *path);
    /* A per-item error or warning, worded the way 7zz prints it. */
    void (*message)(void *context, const char *message);
} SevenZipCallbacks;

/* ═══════════════════════════════════════════════════════════════
 * Listing (7zz l -slt)
 * ═══════════════════════════════════════════════════════════════ */
typedef struct SevenZipListing SevenZipListing;

typedef struct {
    const char *path;        /* path inside the archive */
    const char *method;      /* e.g. "LZMA2:24", "" if unknown */
    uint64_t    size;
    uint64_t    packed_size;
    int64_t     mtime;       /* Unix time in seconds, 0 if unknown */
    uint32_t    crc;
    uint32_t    attributes;  /* 7-Zip attribute word, 0 if unknown */
    bool        has_crc;
    bool        is_dir;
    bool        encrypted;
} SevenZipItem;

/* password: NULL when none is known yet. A compressed tar (tar.gz, tar.xz, …)
   is listed as the tar inside it. */
int32_t sevenzip_list(const char *archive, const char *password, SevenZipListing **listing);
void sevenzip_listing_free(SevenZipListing *listing);

/* Innermost archive type as 7zz reports it: "7z", "Rar5", "Rar", "zip", "tar", … */
const char *sevenzip_listing_type(const SevenZipListing *listing);
/* Outer layer when the archive is nested ("gzip" for a tar.gz), "" otherwise. */
const char *sevenzip_listing_container(const SevenZipListing *listing);
bool sevenzip_listing_is_solid(const SevenZipListing *listing);
uint32_t sevenzip_listing_volumes(const SevenZipListing *listing);
/* True when the archive could only be opened with a password (7z -mhe, rar -hp). */
bool sevenzip_listing_headers_encrypted(const SevenZipListing *listing);
uint32_t sevenzip_listing_count(const SevenZipListing *listing);
/* The item's strings stay valid until sevenzip_listing_free(). */
bool sevenzip_listing_item(const SevenZipListing *listing, uint32_t index, SevenZipItem *item);

/* ═══════════════════════════════════════════════════════════════
 * Extract and test (7zz x / t)
 * ═══════════════════════════════════════════════════════════════ */

/* items: paths inside the archive, each with everything under it;
   NULL or item_count 0 extracts everything. */
int32_t sevenzip_extract(
    const char              *archive,
    const char              *destination,
    const char *const       *items,
    size_t                   item_count,
    int32_t                  overwrite,
    const char              *password,
    const SevenZipCallbacks *callbacks
);

int32_t sevenzip_test(const char *archive, const char *password, const SevenZipCallbacks *callbacks);

/* ═══════════════════════════════════════════════════════════════
 * Create, add and delete (7zz a / d)
 * ═══════════════════════════════════════════════════════════════ */
typedef struct {
    const char *format;          /* -t: "7z", "zip", "tar", "gzip", "xz", "bzip2" */
    int32_t     level;           /* -mx: 0…9, negative for the format default */
    int32_t     solid;           /* -ms: 1 on, 0 off, negative for the format default */
    const char *password;        /* -p: NULL for no encryption */
    bool        encrypt_headers; /* -mhe=on (7z) */
    bool        zip_aes256;      /* -mem=AES256 (zip) */
    uint64_t    volume_size;     /* -v…b: 0 for a single file */
    bool        delete_sources;  /* -sdel */
} SevenZipUpdateOptions;

/* Creates the archive or adds sources (files or folders) to an existing one;
   each source is stored under its own name. */
int32_t sevenzip_update(
    const char                  *archive,
    const char *const           *sources,
    size_t                       source_count,
    const SevenZipUpdateOptions *options,
    const SevenZipCallbacks     *callbacks
);

int32_t sevenzip_delete(
    const char              *archive,
    const char *const       *items,
    size_t                   item_count,
    const char              *password,
    bool                     encrypt_headers,
    const SevenZipCallbacks *callbacks
);

/* ═══════════════════════════════════════════════════════════════
 * Diagnostics
 * ═══════════════════════════════════════════════════════════════ */

/* Message of the last failed call on this thread, "" if none. Valid until
   the next call on the same thread. */
const char *sevenzip_last_error(void);
/* "<7-Zip version>+MacRAR.Patch.<n>" */
const char *sevenzip_get_version(void);

#ifdef __cplusplus
}
#endif

#endif /* SEVENZIP_APPLE_H */
