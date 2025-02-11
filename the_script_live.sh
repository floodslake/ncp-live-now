#!/bin/bash


set -e
set -o pipefail
set -u


curl --version >/dev/stderr
jq --version >/dev/stderr
sort --version >/dev/stderr


offset_second="$1"
channel_list_json="$2"

file "${channel_list_json}" >/dev/stderr

now_second=$(date '+%s');
limit_second=$((${now_second} + ${offset_second}));


# collect live

declare -A live_timestamp_code_row_map

while read -r channel_info; do
  fanclub_site_id="$(jq --raw-output '.id' <<<"${channel_info}")";
  domain="$(jq --raw-output '.domain' <<<"${channel_info}")";

  live_page_info="$(
    curl -sS \
      -H 'fc_use_device: null' \
      "https://api.nicochannel.jp/fc/fanclub_sites/${fanclub_site_id}/live_pages?page=1&live_type=1&per_page=1" | \
    jq '.data' \
  )";

  if [[ "${live_page_info}" != 'null' ]]; then
    live_list="$(jq '.video_pages.list' <<<"${live_page_info}")";

    if [[ "${live_list}" != '[]' ]]; then
      content_code="$(jq --raw-output '.[0].content_code' <<<"${live_list}")";

      echo "processing [${domain}/live/${content_code}]" >/dev/stderr

      live_info="$(
        curl -sS \
          -H 'fc_use_device: null' \
          "https://api.nicochannel.jp/fc/video_pages/${content_code}" | \
        jq '.data.video_page' \
      )";

      live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";
      live_started_at="$(jq --raw-output '.live_started_at' <<<"${live_info}")";

      video_allow_dvr_flg="$(jq --raw-output '.video.allow_dvr_flg' <<<"${live_info}")";
      [[ "${video_allow_dvr_flg}" == 'true' ]] && video_allow_dvr_flg='';

      video_convert_to_vod_flg="$(jq --raw-output '.video.convert_to_vod_flg' <<<"${live_info}")";
      [[ "${video_convert_to_vod_flg}" == 'true' ]] && video_convert_to_vod_flg='';
      
      video_free="$(jq --raw-output '.video.start_with_free_part_flg' <<<"${live_info}")";
      [[ "${video_free}" == 'true' ]] && video_free='';

      live_scheduled_start_at_second=$(date --date="${live_scheduled_start_at}" '+%s');
      live_started_at_second=$(date --date="${live_started_at}" '+%s');

      title="$(jq --raw-output '.title' <<<"${live_info}")";

      thumbnail_url="$(jq --raw-output '.thumbnail_url' <<<"${live_info}")";
      if [[ "${thumbnail_url}" != 'null' ]]; then
        thumbnail_element="<img src=\"${thumbnail_url}\" height=\"72\" style=\"display: block;\">"
      else
        thumbnail_element='<i>no thumbnail</i>'
      fi;
      
      if [[ "${video_allow_dvr_flg}" == 'false' ]]; then
        status_dvr='&#10060'
      else
        status_dvr=""
      fi;
      
      if [[ "${video_convert_to_vod_flg}" == 'false' ]]; then
        status_vod='&#10060'
      else
        status_vod=""
      fi;

      if [[ "${video_free}" == 'false' ]]; then
        status_free='&#10060'
      else
        status_free=""
      fi;

      key="${live_started_at_second} ${content_code}"
      value="$(
        cat <<-TABLE_ROW
			<tr>
				<td><a href="${domain}/lives" rel="noreferrer noopener" target="_blank">${thumbnail_element}</a></td>
				<td>${live_started_at} <a href="${domain}/live/${content_code}" rel="noreferrer noopener" target="_blank">${content_code}</a> &#x1F534<br>${title}</td>
				<td>${status_dvr}</td>
				<td>${status_vod}</td>
				<td>${status_free}</td>
			</tr>
			TABLE_ROW
      )"
      live_timestamp_code_row_map["${key}"]="${value}"

      echo -e '\t''collected live' >/dev/stderr
    fi;
  fi;
done < <(<"${channel_list_json}" jq --compact-output '.data.content_providers | .[]')

echo "count of incoming live = ${#live_timestamp_code_row_map[@]}" >/dev/stderr

# sort live

declare -a live_timestamp_code_array

while read live_timestamp_code; do
  live_timestamp_code_array+=("${live_timestamp_code}")
done < <(
  for live_timestamp_code in "${!live_timestamp_code_row_map[@]}"; do
    echo "${live_timestamp_code}"
  done | \
  sort -k 1
)


# draw table
echo '<table>'

cat <<'TABLE_HEADER'
  <thead>
    <th>Thumbnail</th>
    <th>START (UTC), URL & Title</th>
    <th>DVR</th>
    <th>VOD</th>
    <th>FREE?</th>
  </thead>
TABLE_HEADER

for key in "${live_timestamp_code_array[@]}"; do
  echo "${live_timestamp_code_row_map["${key}"]}"
done

echo '</table>'
