$(document).ready(function() {
    $('a[data-toggle="popup"]').each(function() {
        $(this).popup({
            popup: $(this).attr('data-content'),
            position: $(this).attr('data-position'),
            on: 'click'
        })
    });

    $('a[data-toggle="slide"]').on('click', function(e) {
        e.preventDefault();

        var target = this.hash;
        var $target = $(target);

        $('html, body').stop().animate({
            'scrollTop': $target.offset().top - 60
        }, 900, 'swing');
    });

    $('#verticalMenu').niceScroll({ cursorcolor: "transparent" });
    $('.ui.accordion').accordion();
    $('.ui.dropdown').dropdown();
    $('.ui.checkbox').checkbox();
    $('.ui.progress').progress();

    $('#showToggle').hide();
    $('#hideToggle').show();
    $('#hideToggle').click(function() {
        $('#hideToggle').hide();
        $('#showToggle').show();
        $('#sideMenu').addClass('hide');
    });
    $('#showToggle').click(function() {
        $('#showToggle').hide();
        $('#hideToggle').show();
        $('#sideMenu').removeClass('hide');
    });
});
