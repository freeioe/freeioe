$(document).ready(function() {

  // selector cache
  var
    // alias
    handler
  ;

  $('.ui.checkbox').checkbox({
    onChecked: function() {
      $(this).closest('.table').find('.button').removeClass('disabled');
    }
  });


});
