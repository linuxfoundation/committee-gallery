# Embeddable Committee Gallery for LF Project WordPress sites

[![License](https://img.shields.io/github/license/jmertic/committee-gallery)](LICENSE)
[![Build](https://github.com/jmertic/committee-gallery/actions/workflows/jekyll.yml/badge.svg)](https://github.com/jmertic/committee-gallery/actions/workflows/jekyll.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=jmertic_committee-gallery&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=jmertic_committee-gallery)

Many of our LF Projects use the 'Persons' post type to display the list of committee members on the project website. Since committee management is handled in LFX, the website must be manually synchronized to ensure accuracy. While committee member changes are usually only a few times a month, we see headshots, titles, and bios change from time to time, and those need to be synced.

This project aims to pull the committee member list and member information and display it using the same HTML used on the LF project websites or in other embeds or visuals, such as slide decks.

## Adding a committee

It’s an easy one-step process to add a new committee. Add a new page in the root directory with the extension `.md` with the contents as below.

```markdown
---
lfx_committee_uid: <committee UID from LFX Self Serve - example b3a036b9-5d6f-4ebb-9968-49c598924c14>
render: # optional, defaults to 'slidedeck'
filter: # optional, defaults to 'voting'
---
```

You can use `lfx_committee_url` with a link to the committee in LFX Self Serve instead; the committee UID is taken from the link. Links to the old PCC (`projectadmin.lfx.linuxfoundation.org`) carry v1 committee IDs that don't exist in LFX Self Serve, so the build stops with an error on them.

### API access

Committee members are read from the LFX Self Serve query service (`GET /query/resources?type=committee_member&tags=committee_uid:<uid>`). Unlike the old public PCC endpoint, committee members are not public in LFX Self Serve, so the build needs a bearer token:

- `LFX_API_TOKEN` (required) - set as a repository secret; the build workflows pass it to Jekyll. The identity behind it must be able to view every committee listed here.
- `LFX_API_URL` (optional) - defaults to `https://lfx-api.v2.cluster.lfx.dev`.
- `LFX_ALLOW_EMPTY_COMMITTEES=1` (optional) - by default a committee that returns no members fails the build, since that almost always means a wrong UID or missing access rather than an empty committee.

Member email addresses are returned by the API but never written to the generated pages.

Options for `render` are:

- [`oldsite`](_includes/oldsite.html) is the HTML layout most LF project websites used from 2021 or earlier.
- [`newsite`](_includes/newsite.html) is for LF project websites from 2022 and newer.
- [`slidedeck`](_includes/slidedeck.html) is for including a committee headshot list in a slide deck. (default option)

Options for `filter` are:

- `all` - returns all rows.
- `allbutstaff` - returns all records with `Role != 'LF Staff'`.
- `alternates` - returns all records with `Voting Status = 'Alternative Voting Rep'`.
- `memberreps` - returns all records with `AppointedBy = 'Membership Entitlement'`.
- `staff` - returns all records with `Role = 'LF Staff'`.
- `voting` - returns all records with `Voting Status = 'Voting Rep'`. (default option)
- `voting-and-alternates` - returns all records with `Voting Status = 'Voting Rep' or 'Alternative Voting Rep'`.

If you need to add additional content or CSS for rendering, you can do this after the front matter. 

## Getting the committee data correct

Each member's name, job title, organization, role, voting status, appointed-by and LinkedIn URL come from the committee member record in LFX Self Serve; edit them there.

Headshots come from the member's LFX profile picture, which LFX copies onto each committee member record. Bios, Twitter and GitHub aren't available from LFX Self Serve, so those are blank on generated pages. To override a headshot or supply a missing one, add an image to the `_profile_images` folder named with the member's LFX username (or their committee member UID), e.g. `_profile_images/jdoe.jpg`. Set `default_headshot` in `_config.yml` to use a placeholder image for everyone else.

## Hosting on a website

For WordPress, you can remove the Persons block in the page editor and replace it with a ‘Raw HTML’ block with the contents as below:

```html
<div w3-include-html="https://jmertic.github.io/committee-gallery/FILENAME.html"></div>
<script src="https://jmertic.github.io/committee-gallery/embed.js"></script>
```

`FILENAME` matches the filename of the file created, substituting `.md` with `.html`.

# Contributing

Issues and pull requests to fix issues or add new renders or filters are always welcome.

## Current list of committees and renders

See [here](https://jmertic.github.io/committee-gallery)

