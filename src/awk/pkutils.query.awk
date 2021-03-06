#
# Copyright (c) 2019 Valery Timiriliyev timiriliyev@gmail.com
# 
# This software is provided 'as-is', without any express or implied
# warranty. In no event will the authors be held liable for any damages
# arising from the use of this software.
# 
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
# 
# 1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.
#

@include "pkutils.version-compare"

# pkutils.query.awk
# Functions to work with the internal database.
# The entire database is kept in RAM for performance,
# so pkutils is *HIGHLY* RAM-consuming.


# --------------------------------
# -- compare_packages
#    -1: pk1 is older
#     0: identical packages
#     1: pk1 is newer
# 32768: identical packages, but different tags
# 65536: different packages
# --------------------------------
function compare_packages(pk1, pk2,    status) {
    if (pk1["name"] != pk2["name"]) {
        return 65536;
    }
    status = compare_versions(pk1["version"], pk2["version"]);
    if (status != 0) {
        return status;
    }
    if (pk1["build"] > pk2["build"]) {
        return 1;
    } else if (pk1["build"] < pk2["build"]) {
        return -1;
    }
    if (pk1["tag"] != pk2["tag"]) {
        return 32768;
    }
    return 0;
}

# --------------------------------
# -- get_remote_package_status
#   -1: downgrade is possible
#    0: installed
#    1: upgrade is possible
#  32K: other tag
# 128K: not installed
# --------------------------------
function get_remote_package_status(pk,    i, rc) {
    for (i = DB["first_local"]; i <= DB["length"]; i++) {
        rc = compare_packages(pk, DB[i]);
        if (rc == 65536) {
            # different package, skip
            continue;
        }
        return rc;
    }
    return 131072;
}

# --------------------------------
# -- get_local_package_status
#     0: latest
#     1: upgradable
# 65536: orphan
# --------------------------------
function get_local_package_status(pk,    i, rc, status) {
    # let's assume that the local package is orphan
    status = 65536;
    for (i = 1; i <= DB["last_remote"]; i++) {
        rc = compare_packages(pk, DB[i]);
        if (rc == 65536) {
            # different package, skip
            continue;
        } else if (rc == -1) {
            # local package is older
            status = 1;
        } else if (rc == 0 && status == 65536) {
            # if there is no upgrade, then the latest version is here already
            status = 0;
        }
    }
    return status;
}

# --------------------------------
# -- get_package_status
#   -1: downgradable
#    0: installed
#    1: upgradable
#  32K: other tag
#  64K: orphan
# 128K: not installed
# --------------------------------
function get_package_status(id,    i, total, rc, status) {
    if (id <= DB["last_remote"]) {
        return get_remote_package_status(DB[id]);
    }
    return get_local_package_status(DB[id]);
}

# --------------------------------
# -- pk_get_package_id_by_name
# Get package index in DB by it's name
# Polucith index packeta po ego nazvanyu
# --------------------------------
function db_get_by_name(name, desired_repo,    i, j, k, cases) {
    k = split(name, cases, /\|/);
    for (i = 1; i <= DB["length"]; i++) {
        for (j = 1; j <= k; j++) {
            if (desired_repo && DB[i]["repo_id"] != desired_repo) {
                continue;
            }
            if (DB[i]["name"] == cases[j]) {
                return i;
            }
        }
    }
    return 0;
}

# --------------------------------
# -- db_get_signature
# Vozvrasceaet signaturu packeta,
# to esth strocu vida `1.0.0-i586-1_slack14.2'
# --------------------------------
function db_get_signature(pk) {
    if (pk["type"] == "SlackBuild") {
        return pk["version"];
    }
    return sprintf("%s-%s-%d%s",
        pk["version"],
        pk["arch"],
        pk["build"],
        pk["tag"]);
}

# --------------------------------
# -- db_get_signature
# Vozvrasceaet polnoe imea packeta,
# to esth `imea-signatura'.
# --------------------------------
function db_get_full_name(pk) {
    return sprintf("%s-%s", pk["name"], db_get_signature(pk));
}

# --------------------------------
# -- db_get_tar_name
# Vozvrasceaet nazvanie sobstvenno faila
# dlea packeta s t?z-rasxireniem.
# --------------------------------
function db_get_tar_name(pk) {
    if (pk["type"] == "SlackBuild") {
        return sprintf("%s.tar.gz", pk["name"]);
    }
    return sprintf("%s.%s", db_get_full_name(pk), pk["type"]);
}

# --------------------------------
# -- db_rebuild
# --------------------------------
function db_rebuild(    m, cmd, index_dat, total) {
    index_dat = DIRS["lib"] "/index.dat";
    FPAT = "[^,]*|\"[^\"]*\"";
    while ((getline < index_dat) > 0) {
        total++;
        DB[total]["repo_id"]     = $1;
        DB[total]["location"]    = $2;
        DB[total]["series"]      = $3;
        DB[total]["name"]        = $4;
        DB[total]["version"]     = $5;
        DB[total]["arch"]        = $6;
        DB[total]["build"]       = $7;
        DB[total]["tag"]         = $8;
        DB[total]["type"]        = $9;
        DB[total]["checksum"]    = $10;
        DB[total]["description"] = $11;
        DB[total]["required"]    = $12;
        DB[total]["conflicts"]   = $13;
        DB[total]["suggests"]    = $14;
        DB[total]["src_download"] = $15;
        DB[total]["src_download_x86_64"] = $16;
        DB[total]["src_checksum"] = $17;
        DB[total]["src_checksum_x86_64"] = $18;
    }
    close(index_dat);

    DB["last_remote"] = total;
    DB["first_local"] = total + 1;

    cmd = sprintf("find %s/var/log/packages -type f -printf \"%%f\\n\" 2> /dev/null", DIRS["root"]);
    FS = " "; RS = "\n";
    while ((cmd | getline) > 0) {
        match($0, /^(.*)-([^-]*)-([^-]*)-([0-9])([^-]*)$/, m);
        total++;
        DB[total]["repo_id"]     = "local";
        DB[total]["series"]      = "unknown";
        DB[total]["name"]        = m[1];
        DB[total]["version"]     = m[2];
        DB[total]["arch"]        = m[3];
        DB[total]["build"]       = m[4];
        DB[total]["tag"]         = m[5];
        DB[total]["description"] = "(description not available)";
    }
    close(cmd);

    DB["length"] = total;
}

# --------------------------------
# -- pkexpr
# get[1] -> name
# get[2] -> arch
# get[3] -> version
# get[4] -> tag
# get[5] -> repo_id
# get[6] -> series
# Format of pkexpr:
# app~i586=1.3.0!_slack14.2@slackware64:xap
# --------------------------------
function pkexpr(query, strong, get,    i) {
    match(query,
        /^([^~=!@:]*)~?([^~=!@:]*)=?([^~=!@:]*)!?([^~=!@:]*)@?([^~=!@:]*):?([^~=!@:]*)/,
        get);

    for (i = 1; i <= 6; i++) {
        if (!get[i]) {
            get[i] = ".*";
        }
        if ((strong || OPTIONS["strong"]) || i > 1) {
            get[i] = "^" get[i] "$";
        }
    }
}

# --------------------------------
# -- perform_query
# --------------------------------
function perform_query(results, query, strong,    i, j, f, get) {
    pkexpr(query, strong, get);

    for (i = 1; i <= DB["length"]; i++) {
        if ((DB[i]["name"] ~ get[1]) &&
            (DB[i]["arch"] ~ get[2]) &&
            (DB[i]["version"] ~ get[3]) &&
            (DB[i]["tag"] ~ get[4]) &&
            (DB[i]["repo_id"] ~ get[5]) &&
            (DB[i]["series"] ~ get[6]))
        {
            if (strong) {
                for (j = 1; j <= results["length"]; j++) {
                    if (DB[results[j]]["name"] == DB[i]["name"]) {
                        # ispolhzuem flag, t.c. net vozmoghnosti
                        # normalhno vhyti iz vlogennogo cycla
                        f = 65535;
                    }
                }
                if (f == 65535) {
                    break;
                }
            }
            results[++results["length"]] = i;
        }
    }
}

# --------------------------------
# -- db_query
# --------------------------------
function db_query(results, queries,    i) {
    for (i = 1; i <= queries["length"]; i++) {
        perform_query(results, queries[i], 1);
    }
}

# --------------------------------
# -- db_weak_query
# --------------------------------
function db_weak_query(results, queries,    i) {
    for (i = 1; i <= queries["length"]; i++) {
        perform_query(results, queries[i]);
    }
}

# --------------------------------
# -- db_is_locked
# --------------------------------
function db_is_locked(p,    i, get) {
    for (i = 1; i <= LOCK["length"]; i++) {
        pkexpr(LOCK[i], 0, get);
        if ((DB[p]["name"] ~ get[1]) &&
            (DB[p]["arch"] ~ get[2]) &&
            (DB[p]["tag"] ~ get[3]) &&
            (DB[p]["version"] ~ get[4]) &&
            (DB[p]["repo_id"] ~ get[5]) &&
            (DB[p]["series"] ~ get[6]))
        {
            return i;
        }
    }
    return 0;
}

# --------------------------------
# -- db_is_installed
# Etot bratixhca provereaet, ustanovlen li
# tot ili inoi packet. Na vxod DB y index packeta,
# a na vhixod 1, esli packet ustanovlen localhno,
# libo 65535 + index obnovleaemogo packeta, esli
# ustanovlena drugaya versia, libo 0, esli nicego net.
# --------------------------------
# Pocemu 65535? Potomu chto mogu.
# --------------------------------
# Be sure to pass here REMOTE package index.
# --------------------------------
function db_is_installed(p,    i) {
    for (i = DB["first_local"]; i <= DB["length"]; i++) {
        if (DB[i]["name"] != DB[p]["name"]) {
            continue;
        }

        k = db_is_locked(i);
        if (k >= 1) {
            return 32767 + k;
        }

        if (DB[p]["type"] == "SlackBuild") {
            if (DB[i]["version"] == DB[p]["version"]) {
                return 1;
            }
            return 65535 + i;
        }

        if ((DB[i]["version"] == DB[p]["version"]) &&
            (DB[i]["arch"] == DB[p]["arch"]) &&
            (DB[i]["build"] == DB[p]["build"]) &&
            (DB[i]["tag"] == DB[p]["tag"]))
        {
            return 1;
        }
        return 65535 + i;
    }

    return 0;
}

# --------------------------------
# -- db_is_upgradable
# Checks if local package is upgradable.
# Be sure to pass here LOCAL package index.
# --------------------------------
function db_is_upgradable(p,    i, k) {
    k = db_is_locked(p);
    if (k >= 1) {
        return 32767 + k;
    }

    for (i = 1; i <= DB["last_remote"]; i++) {
        if (DB[i]["name"] == DB[p]["name"]) {
            if (DB[i]["type"] == "SlackBuild") {
                if (DB[i]["version"] != DB[p]["version"]) {
                    return 65535 + i;
                } else {
                    return 1;
                }
            }

            if ((DB[i]["version"] != DB[p]["version"]) ||
                (DB[i]["arch"] != DB[p]["arch"]) ||
                (DB[i]["build"] != DB[p]["build"]) ||
                (DB[i]["tag"] != DB[p]["tag"]))
            {
                return 65535 + i;
            } else {
                return 1;
            }
        }
    }
    return 0;
}

# --------------------------------
# -- db_dump
# --------------------------------
function db_dump(    i, j) {
    printf "DB size: %d (%d) packages\n\n", DB["length"], DB["last_remote"];
    for (i = 1; i <= DB["length"]; i++) {
        printf "== PACKAGE #%d ==\n", i;
        for (j in DB[i]) {
            printf "  %s: %s\n", j, DB[i][j];
        }
        printf "\n";
    }
}
