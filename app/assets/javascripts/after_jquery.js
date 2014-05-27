$('html').removeClass('no-js').addClass('js');


var me, editable_map, editable_marker;
function make_map(map_div, hide_self) {
  if (me == undefined) {
    me = L.latLng($('body').data('lat'), $('body').data('lng'));
  }
  var map = new L.Map(map_div, { center: me, zoom: 10, minZoom: 3, maxZoom: 18,
    layers: [new L.TileLayer('http://{s}.mqcdn.com/tiles/1.0.0/osm/{z}/{x}/{y}.png', {
      attribution: 'Data &copy; <a href="http://www.openstreetmap.org/">OpenStreetMap</a> contributors; Tiles by <a href="http://www.mapquest.com/">MapQuest</a>',
      subdomains: ['otile1','otile2','otile3','otile4']
      })]
    });
  if (!hide_self) {
    L.marker(me, {icon: L.divIcon({className: 'me', html: '<div class="inner"></div>', iconSize: L.point(15, 15)})}).addTo(map);
  }
  return map;
}
function finish_map(map, points) {
  points.push(me);
  if (points.length > 1) {
    map.fitBounds(points, {padding: [20, 20]});
  }
}
function marker_dragged(e) {
  ll = e.target.getLatLng();
  $('#coords input:first').val(ll.lat);
  $('#coords input:last').val(ll.lng);
}


$(function(){

  // add maps
  $('*[data-map]').each(function(){
    var container = $(this);
    var map_div = '<div class="map" id="map_' + container.attr('id') + '"></div>';
    if (container.data('map') == 'side') {
      container.find('ol, ul').wrap('<div class="colA"></div>').parent().wrap('<div class="cols"></div>').parent().after('<div class="clearfix"></div>').append(map_div);
    }
    else {
        container.append(map_div);
    }
    var map = make_map('map_' + container.attr('id'));
    var points = [];
    var singleton = container.data('lat'); // use as boolean
    $(singleton ? container : container.find('*[data-lat]')).each(function(){
      var point = L.latLng($(this).data('lat'), $(this).data('lng'));
      points.push(point);
      var marker = L.marker(point).addTo(map);
      if (!singleton) {
        marker.bindPopup($(this).children().length ? $(this).html() : $('<div>').append($(this).clone()).html());
      }
    });
    finish_map(map, points);
  });

  // form stuff
  $('form a').attr('target', '_new');
  $("form[method!='get']")
    // expand/contract input as content changes length
    .find("input[data-default_size]").on('keyup paste blur', function(){
      $(this).attr('size', Math.min(100, Math.max($(this).data('default_size'), $(this).val().length + 3)));
    })
    // allow form submission by hitting 'enter' key. this is needed as the 'cancel' button precedes the 'save' button and hitting enter would thus 'cancel' and do nothing
    .find("input[type='text'], input[type='email'], input[type='number'], input[type='tel']").keypress(function(e) {
      if (e.keyCode == 13) {
        $(this).parentsUntil('form').parent().submit();
        e.preventDefault();
        return false;
      }
    });

});