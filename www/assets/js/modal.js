$(document).ready(function() {
  // selector cache
  var
    // alias
    handler
  ;

  // event handlers
  handler = {

  };

    $('.animation.dropdown')
      .dropdown({
        onChange: function(value) {
          $('.standard.test.modal')
            .modal('setting', 'transition', value)
            .modal('show')
          ;
        }
      })
    ;
    $('.ui.checkbox')
      .checkbox()
    ;


});
