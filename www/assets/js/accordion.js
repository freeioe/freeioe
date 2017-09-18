$(document).ready(function() {

  // selector cache
  var
    $accordion     = $('.ui.accordion'),
    $menuAccordion = $('.ui.menu.accordion'),
    $checkbox      = $('.ui.checkbox'),
    // alias
    handler
  ;
  $accordion
    .accordion()
  ;
  $menuAccordion
    .accordion({
     exclusive: false
    })
  ;
  $checkbox
    .checkbox()
  ;

});

