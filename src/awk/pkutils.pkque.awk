
@include "pkutils.foundation.awk"
@include "pkutils.query.awk"
@include "pkutils.deps.awk"

function parse_arguments(queries,    i, m) {
    for (i = 1; i < ARGC; i++) {
        if (ARGV[i] ~ /^-[^=]+$/) {
            if (ARGV[i] ~ /^(-A|--show-all)$/) {
                OPTIONS["show_all"] = 1;
            } else if (ARGV[i] ~ /^(-D|--show-deps)$/) {
                OPTIONS["show_deps"] = 1;
            }
        } else if (ARGV[i] ~ /^-([^=]+)=([^=]+)$/) {
            match(ARGV[i], /^([^=]+)=([^=]+)$/, m);

            if (m[1] ~ /^-R$|^--root$/) {
                OPTIONS["root"]  = m[2];
            } else {
                printf "Unrecognized option: %s\n", m[1];
                return 0;
            }
        } else {
            queries[++queries["length"]] = ARGV[i];
        }
    }

    return 1;
}

function pkque_print_package(pk) {
    printf "\n%s:%s/%s %s\n  %s\n",
        pk["repo_id"], pk["series"], pk["name"],
        pk_get_full_version(pk),
        pk["description"];
}

function pkque_main(    i, p, queries, results, dlist, fmt, j, stash) {
    if (!parse_arguments(queries)) {
        return 1;
    }

    pk_setup_dirs(OPTIONS["root"]);
    if (!pk_check_dirs()) {
        printf "Run `pkupd' first.\n";
        return 255;
    }
    pk_parse_options();

    printf "Reading packages index...";
    db_rebuild();
    printf " Done.\n";

    db_weak_query(results, queries);
    if (results["length"] <= 0) {
        printf "No packages found.\n";
        return 0;
    }

    for (i = 1; i <= results["length"]; i++) {
        p = results[i];

        if (!OPTIONS["show_all"] && DB[p]["repo_id"] == "local") {
            continue;
        }

        printf "\n%s:%s/%s %s\n  %s\n",
            DB[p]["repo_id"],
            DB[p]["series"],
            DB[p]["name"],
            db_get_signature(DB[p]),
            DB[p]["description"];
        
        if (!OPTIONS["show_deps"]) {
            continue;
        }

        delete dlist;
        make_dependency_list(p, dlist);
        if (dlist["length"] <= 1) {
            printf "No dependencies or information is not available.\n";
            continue;
        }

        for (j = dlist["length"]; j >= 1; j--) {
            if (dlist[j] in stash) {
                continue;
            }
            stash[dlist[j]] = 65535;
            stash["size"]++;
            fmt = sprintf("  %%%ds* %%s\n", dlist[j, "level"] * 2);
            printf fmt, "", DB[dlist[j]]["name"];
        }

        printf "\n  Total dependencies: %d/%d.\n", stash["size"], dlist["length"];
    }

    if (results["length"] > 5) {
        printf "\nTotal packages found: %d.\n", results["length"];
    }

    printf "\n";
    return 0;
}

BEGIN {
    rc = pkque_main();
    exit rc;
}
