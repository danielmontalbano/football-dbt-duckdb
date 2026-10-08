{#
    Football normalisation helper.

    Raw counts are misleading: a full-back who played 90 minutes will always
    have more off-ball runs than a substitute who played 12. We normalise per
    30 minutes of *possession-adjusted* time:

      - in-possession metrics (runs, passing options) -> per 30 min TIP
      - out-of-possession metrics (pressing)          -> per 30 min OTIP

    30 minutes is roughly the time an average team spends in possession per
    match, so "per 30" reads on a similar scale to a familiar "per 90".
#}
{% macro per_30(metric, minutes) %}
    case when {{ minutes }} > 0 then round({{ metric }} * 30.0 / {{ minutes }}, 2) end
{% endmacro %}
