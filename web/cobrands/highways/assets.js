(function(){

if (!fixmystreet.maps) {
    return;
}

var defaults = {
    http_options: {
        url: "https://struan.tilma.dev.mysociety.org/mapserver/highways",
        params: {
            SERVICE: "WFS",
            VERSION: "1.1.0",
            REQUEST: "GetFeature",
            SRSNAME: "urn:ogc:def:crs:EPSG::3857"
        }
    },
    format_class: OpenLayers.Format.GML.v3.MultiCurveFix,
    asset_type: 'area',
    max_resolution: 4.777314267158508,
    min_resolution: 0.5971642833948135,
    asset_id_field: 'CENTRAL_AS',
    geometryName: 'msGeometry',
    srsName: "EPSG:3857",
    strategy_class: OpenLayers.Strategy.FixMyStreet
};

var highways_stylemap = new OpenLayers.StyleMap({
    'default': new OpenLayers.Style({
        fill: false,
        stroke: false,
    })
});

fixmystreet.assets.add($.extend(true, {}, defaults, {
    http_options: {
        params: {
            TYPENAME: "Highways"
        }
    },
    stylemap: highways_stylemap,
    always_visible: true,

    non_interactive: true,
    asset_type: 'area',
    road: true,
    all_categories: true,
    nearest_radius: 15,
    actions: {
        found: function(layer, feature) {
            // this is to stop this firing when we change category
            if ( fixmystreet.body_overrides.highways_override ) {
                // but if we've changed location then we want to reset things
                var lat = $('#fixmystreet\\.latitude').val(),
                    lon = $('#fixmystreet\\.longitude').val();
                if ( lat == fixmystreet.body_overrides.location.latitude &&
                     lon == fixmystreet.body_overrides.location.longitude ) {
                    return;
                }
                fixmystreet.body_overrides.highways_override = false;
            }
            $('#highways').remove();
            if ( !fixmystreet.assets.selectedFeature() ) {
                fixmystreet.body_overrides.only_send('Highways England');
                add_highways_warning(feature.attributes.ROA_NUMBER);
            }
        },
        not_found: function(layer) {
            fixmystreet.body_overrides.highways_override = false;
            fixmystreet.body_overrides.remove_only_send();
            $('#highways').remove();
        }
    }
}));

function add_highways_warning(road_name) {
  var $warning = $('<div class="box-warning" id="highways"><p>It looks like you clicked on the ' + road_name + ' which is managed by <strong>Highways England</strong>.<p></div>');
    $('<a>')
        .attr('href', '#')
        .attr('id', 'js-not-highways')
        .html('Send to <strong>' + fixmystreet.bodies.join('</strong> ' + translation_strings.or + ' <strong>') + '</strong> instead.')
        .on('click', function() {
            fixmystreet.body_overrides.highways_override = true;
            fixmystreet.body_overrides.location = {
                latitude: $('#fixmystreet\\.latitude').val(),
                longitude: $('#fixmystreet\\.longitude').val()
            };
            fixmystreet.body_overrides.remove_only_send();
            $('#highways').remove();
            add_highways_reset(road_name);
        })
        .appendTo($warning);
    $('.change_location').after($warning);
}

function add_highways_reset(road_name) {
  var $not_highways = $('<div class="box-warning" id="highways"><p>Although you are reporting a problem near the ' + road_name + ' which is managed by <strong>Highways England</strong> you&rsquo;ve indicated you want to send the report to <strong>' + fixmystreet.bodies.join('</strong> ' + translation_strings.or + ' <strong>') + '</strong>.<p></div>');
    $('<a>')
        .attr('href', '#')
        .attr('id', 'js-is-highways')
    .html('Send to <strong>Highways England</strong> instead.')
        .on('click', function() {
            fixmystreet.body_overrides.highways_override = false;
            fixmystreet.body_overrides.location = null;
            fixmystreet.body_overrides.only_send('Highways England');
            $('#highways').remove();
            add_highways_warning(road_name);
        })
        .appendTo($not_highways);
    $('.change_location').after($not_highways);
}

})();
