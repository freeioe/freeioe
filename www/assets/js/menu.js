
// ready event
$(document).ready(function() {

  // selector cache
  var
    $dropdownItem = $('.ui.menu .dropdown .item'),
    $popupItem    = $('.ui.menu .email.item'),
    $toolbarMenuPopup    = $('.ui.secondary.menu.toolbar .popup.item'),
    $menuItem     = $('.ui.menu a.item, .menu .link.item').not($dropdownItem).not($toolbarMenuPopup),
    $dropdown     = $('.ui.menu .ui.dropdown'),
    $menuPopup    = $('.ui.menu .popup.item').not($toolbarMenuPopup),
    $languageDropdown    = $('.language.dropdown'),
    // alias
    handler = {

      activate: function() {
        if(!$(this).hasClass('dropdown browse')) {
          $(this)
            .addClass('active')
            .closest('.ui.menu')
            .find('.item')
              .not($(this))
              .removeClass('active')
          ;
        }
      },
      toolbar_activate: function() {
      	var menu_obj = $(this);
        menu_obj.popup('hide');
        menu_obj.addClass('clicked');
        setTimeout(function() { menu_obj.removeClass('clicked'); }, 1000);
      },
      toolbar_onshow: function(popup) {
      	return !$(popup).hasClass('clicked');
	  }
    }
  ;

  $dropdown
    .dropdown({
      on: 'hover'
    })
  ;

  $('.main.container .ui.search')
    .search({
      type: 'category',
      apiSettings: {
        action: 'categorySearch'
      }
    });

  $popupItem
    .popup({
      inline   : true,
      hoverable: false,
      popup    : '.ui.fluid.popup',
      position : 'bottom left',
      delay: {
        show: 300,
        hide: 800
      }
    })
  ;

  $menuItem
    .on('click', handler.activate)
  ;

  $toolbarMenuPopup
    .add($languageDropdown)
    .popup({
      position  : 'bottom left',
      inline  : true,
      delay: {
        show: 1000,
        hide: 0
      },
      onShow: handler.toolbar_onshow,
    })
  ;
  $toolbarMenuPopup
    .on('click', handler.toolbar_activate)
  ;

  $menuPopup
    .add($languageDropdown)
    .popup({
      position  : 'bottom center',
      delay: {
        show: 100,
        hide: 50
      }
    })
  ;
});

