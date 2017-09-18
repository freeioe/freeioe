$(document).ready(function() {

  $('.message .close').on('click', function() {
    $(this).closest('.message').transition('fade');
  });

});

